defmodule PoeFlipFinderWeb.FlipFinderLive do
  @moduledoc """
  The composition root -- mirrors App.tsx's role in the React app. Owns
  every piece of page state (league selection, ingestion freshness, flip
  opportunities, filters/sort/thresholds, favorites, the ratio calculator,
  the row context menu) and renders the whole page in one LiveView rather
  than a separate JSON API plus SPA. See docs/ELIXIR_CODE_STYLE.md's
  Humble Object rule for LiveView -- business logic below is a thin
  wrapper around `PoeFlipFinder.Leagues`, `.Ingestion`, and
  `.FlipOpportunities`; nothing here recomputes what those already own.
  """

  use PoeFlipFinderWeb, :live_view

  alias PoeFlipFinder.{FlipOpportunities, Ingestion, Leagues, RatioCalculator}
  alias PoeFlipFinderWeb.BuildInfo

  @techniques [:vendor_recipe, :exchange_spread, :divination_card, :bulk_buy]
  @sort_columns [:margin, :profit, :volume]
  @sort_directions [:asc, :desc]
  @tabs [:grand_exchange, :vendor, :historical]

  # docs/PRD.md § 7.6/7.7: the in-flight duration is a safety net, not the
  # real dismiss timer -- normally superseded by a completion banner (set
  # via the same set_status_banner/3 helper) well before it would fire.
  @in_flight_banner_ms 60_000
  @completion_banner_ms 6_000
  @ingestion_bucket_seconds 3_600

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:leagues, [])
      |> assign(:selected_league, nil)
      |> assign(:leagues_loading, true)
      |> assign(:leagues_refreshing, false)
      |> assign(:leagues_error, false)
      |> assign(:freshness, nil)
      |> assign(:freshness_loading, true)
      |> assign(:ingestion_refreshing, false)
      |> assign(:freshness_error, false)
      |> assign(:last_refresh_result, nil)
      |> assign(:status_banner, nil)
      |> assign(:status_banner_token, 0)
      |> assign(:opportunities, [])
      |> assign(:opportunities_loading, false)
      |> assign(:opportunities_error, false)
      |> assign(:enabled_techniques, %{
        vendor_recipe: true,
        exchange_spread: true,
        divination_card: true,
        bulk_buy: true
      })
      |> assign(
        :enabled_categories,
        Map.new(category_options(), fn {category, _label} -> {category, true} end)
      )
      |> assign(:category_menu_open, false)
      |> assign(:active_tab, :grand_exchange)
      # Matches the mockup's default state: Margin column active, sorted descending.
      |> assign(:sort_column, :margin)
      |> assign(:sort_direction, :desc)
      |> assign(:thresholds, %{})
      |> assign(:max_start_chaos, nil)
      |> assign(:favorite_route_keys, MapSet.new())
      |> assign(:context_menu, nil)
      |> assign(:ratio_calculator_open, false)
      |> assign(:ratio_text, "")
      |> assign(:ratio_left_text, "")
      |> assign(:ratio_right_text, "")
      |> assign(:ratio_anchor, :left)
      |> assign(:utc_offset_minutes, 0)
      |> assign(:build_hash, BuildInfo.git_hash())
      |> assign(:build_date, BuildInfo.build_date())

    if connected?(socket) do
      send(self(), :load_leagues)
      send(self(), :load_freshness)
    end

    {:ok, socket}
  end

  @impl true
  def handle_info(:load_leagues, socket) do
    leagues = Leagues.resolve_league_list()
    selected = resolve_default_league(leagues)

    socket =
      socket
      |> assign(leagues: leagues, selected_league: selected, leagues_loading: false)
      |> load_opportunities()

    {:noreply, socket}
  end

  def handle_info(:load_freshness, socket) do
    freshness = Ingestion.get_ingestion_freshness()
    {:noreply, assign(socket, freshness: freshness, freshness_loading: false)}
  end

  def handle_info({:clear_status_banner, token}, socket) do
    socket =
      if socket.assigns.status_banner_token == token do
        assign(socket, :status_banner, nil)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_league", %{"value" => external_id}, socket) do
    league = Enum.find(socket.assigns.leagues, &(&1.external_id == external_id))
    {:noreply, socket |> assign(:selected_league, league) |> load_opportunities()}
  end

  def handle_event("refresh_leagues", _params, socket) do
    # Runs the fetch in a Task via start_async, not inline: handle_event only
    # ever reaches the client once it returns, so doing the (potentially
    # multi-second) GGG call synchronously here meant leagues_refreshing:
    # true and its eventual reversal both landed in the SAME diff -- the
    # spinner CSS class existed but the client never had a frame in which
    # it was actually applied. Splitting the assign from the work across
    # this boundary is what makes the spinner visible at all.
    socket =
      socket
      |> assign(:leagues_refreshing, true)
      |> set_status_banner("Refreshing leagues…", @in_flight_banner_ms)

    {:noreply, start_async(socket, :refresh_leagues, &Leagues.refresh_league_list/0)}
  end

  def handle_event("refresh_ingestion", _params, socket) do
    socket =
      socket
      |> assign(:ingestion_refreshing, true)
      |> set_status_banner("Refreshing market data…", @in_flight_banner_ms)

    cap_policy = catchup_cap_policy()

    {:noreply,
     start_async(socket, :refresh_ingestion, fn -> Ingestion.run_ingestion_catchup(cap_policy) end)}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    {:noreply, socket |> assign(:active_tab, tab_atom) |> persist_display_preferences()}
  end

  def handle_event("toggle_technique", %{"technique" => technique}, socket) do
    technique_atom = String.to_existing_atom(technique)
    enabled = Map.update!(socket.assigns.enabled_techniques, technique_atom, &(not &1))
    socket = assign(socket, :enabled_techniques, enabled)
    {:noreply, persist_display_preferences(socket)}
  end

  def handle_event("toggle_category_menu", _params, socket) do
    {:noreply, assign(socket, :category_menu_open, not socket.assigns.category_menu_open)}
  end

  def handle_event("close_category_menu", _params, socket) do
    {:noreply, assign(socket, :category_menu_open, false)}
  end

  def handle_event("toggle_category", %{"category" => category}, socket) do
    category_atom = String.to_existing_atom(category)
    enabled = Map.update!(socket.assigns.enabled_categories, category_atom, &(not &1))
    socket = assign(socket, :enabled_categories, enabled)
    {:noreply, persist_display_preferences(socket)}
  end

  def handle_event("select_all_categories", _params, socket) do
    enabled =
      Map.new(socket.assigns.enabled_categories, fn {category, _enabled} -> {category, true} end)

    socket = assign(socket, :enabled_categories, enabled)
    {:noreply, persist_display_preferences(socket)}
  end

  def handle_event("deselect_all_categories", _params, socket) do
    enabled =
      Map.new(socket.assigns.enabled_categories, fn {category, _enabled} -> {category, false} end)

    socket = assign(socket, :enabled_categories, enabled)
    {:noreply, persist_display_preferences(socket)}
  end

  def handle_event("toggle_sort", %{"column" => column}, socket) do
    column_atom = String.to_existing_atom(column)

    {sort_column, sort_direction} =
      if socket.assigns.sort_column == column_atom do
        {column_atom, flip_direction(socket.assigns.sort_direction)}
      else
        {column_atom, :desc}
      end

    socket = assign(socket, sort_column: sort_column, sort_direction: sort_direction)
    {:noreply, persist_display_preferences(socket)}
  end

  def handle_event("set_threshold", %{"column" => column, "value" => value}, socket) do
    column_atom = String.to_existing_atom(column)

    thresholds =
      case parse_finite_number(value) do
        {:ok, number} -> Map.put(socket.assigns.thresholds, column_atom, number)
        :error -> Map.delete(socket.assigns.thresholds, column_atom)
      end

    socket = assign(socket, :thresholds, thresholds)
    {:noreply, persist_display_preferences(socket)}
  end

  def handle_event("set_max_start", %{"value" => value}, socket) do
    max_start_chaos =
      case parse_finite_number(value) do
        {:ok, number} -> number
        :error -> nil
      end

    socket = assign(socket, :max_start_chaos, max_start_chaos)
    {:noreply, persist_display_preferences(socket)}
  end

  def handle_event("favorites_loaded", %{"route_keys" => route_keys}, socket) do
    {:noreply, assign(socket, :favorite_route_keys, MapSet.new(route_keys))}
  end

  # docs/PRD.md § 7.8/7.9: technique filters, sort column/direction, and
  # threshold values are a per-browser preference like Favorites -- this is
  # the mount-time load, reported by the DisplayPreferencesStorage JS hook
  # from localStorage. Every field is parsed defensively and independently
  # (falling back to that field's own current default) since localStorage
  # content is arbitrary client-controlled data -- corrupted JSON, a value
  # from a future/incompatible version, or hand-edited garbage must never
  # crash the mount, only fall back silently.
  def handle_event("display_preferences_loaded", params, socket) do
    {:noreply,
     assign(socket,
       active_tab: parse_atom_in(params["active_tab"], @tabs, socket.assigns.active_tab),
       enabled_techniques:
         parse_enabled_techniques(params["enabled_techniques"], socket.assigns.enabled_techniques),
       enabled_categories:
         parse_enabled_categories(params["enabled_categories"], socket.assigns.enabled_categories),
       sort_column:
         parse_atom_in(params["sort_column"], @sort_columns, socket.assigns.sort_column),
       sort_direction:
         parse_atom_in(params["sort_direction"], @sort_directions, socket.assigns.sort_direction),
       thresholds: parse_thresholds(params["thresholds"]),
       max_start_chaos: parse_max_start_chaos(params["max_start_chaos"])
     )}
  end

  def handle_event("local_timezone_offset", %{"utc_offset_minutes" => offset}, socket) do
    {:noreply, assign(socket, :utc_offset_minutes, offset)}
  end

  def handle_event("open_context_menu", %{"route_key" => route_key, "x" => x, "y" => y}, socket) do
    is_favorite = MapSet.member?(socket.assigns.favorite_route_keys, route_key)

    {:noreply,
     assign(socket, :context_menu, %{route_key: route_key, x: x, y: y, is_favorite: is_favorite})}
  end

  def handle_event("close_context_menu", _params, socket) do
    {:noreply, assign(socket, :context_menu, nil)}
  end

  def handle_event("toggle_favorite_from_menu", _params, socket) do
    socket =
      case socket.assigns.context_menu do
        nil ->
          socket

        %{route_key: route_key} ->
          updated = toggle_set_membership(socket.assigns.favorite_route_keys, route_key)

          socket
          |> assign(favorite_route_keys: updated, context_menu: nil)
          |> push_event("persist_favorites", %{route_keys: MapSet.to_list(updated)})
      end

    {:noreply, socket}
  end

  def handle_event("toggle_ratio_calculator", _params, socket) do
    {:noreply, assign(socket, :ratio_calculator_open, not socket.assigns.ratio_calculator_open)}
  end

  def handle_event("close_ratio_calculator", _params, socket) do
    {:noreply, assign(socket, :ratio_calculator_open, false)}
  end

  def handle_event("ratio_text_changed", %{"value" => value}, socket) do
    socket = assign(socket, ratio_text: value, ratio_anchor: :left)

    socket =
      case RatioCalculator.simplest_integer_ratio(value) do
        nil ->
          socket

        %{left: left, right: right} ->
          assign(socket, ratio_left_text: to_string(left), ratio_right_text: to_string(right))
      end

    {:noreply, socket}
  end

  def handle_event("ratio_left_changed", %{"value" => value}, socket) do
    socket = assign(socket, ratio_left_text: value, ratio_anchor: :left)
    ratio = RatioCalculator.ratio_value(socket.assigns.ratio_text)

    socket =
      with true <- not is_nil(ratio),
           {:ok, number} <- parse_finite_number(value) do
        assign(
          socket,
          :ratio_right_text,
          RatioCalculator.nearest_right_for_left(number, ratio) |> to_string()
        )
      else
        _ -> socket
      end

    {:noreply, socket}
  end

  def handle_event("ratio_right_changed", %{"value" => value}, socket) do
    socket = assign(socket, ratio_right_text: value, ratio_anchor: :right)
    ratio = RatioCalculator.ratio_value(socket.assigns.ratio_text)

    socket =
      with true <- not is_nil(ratio),
           {:ok, number} <- parse_finite_number(value) do
        assign(
          socket,
          :ratio_left_text,
          RatioCalculator.nearest_left_for_right(number, ratio) |> to_string()
        )
      else
        _ -> socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_async(:refresh_leagues, {:ok, result}, socket) do
    socket =
      case result do
        {:ok, leagues} ->
          selected = resolve_selected_league(leagues, socket.assigns.selected_league)

          socket
          |> assign(
            leagues: leagues,
            selected_league: selected,
            leagues_refreshing: false,
            leagues_error: false
          )
          |> load_opportunities()
          |> set_status_banner("Leagues refreshed", @completion_banner_ms)

        {:error, _reason} ->
          # docs/PRD.md § 7.7: a failure keeps leagues_error as the sole
          # source of truth -- the banner is cleared, not repurposed to
          # report the failure too.
          socket
          |> assign(leagues_refreshing: false, leagues_error: true)
          |> clear_status_banner()
      end

    {:noreply, socket}
  end

  def handle_async(:refresh_leagues, {:exit, _reason}, socket) do
    socket =
      socket
      |> assign(leagues_refreshing: false, leagues_error: true)
      |> clear_status_banner()

    {:noreply, socket}
  end

  def handle_async(:refresh_ingestion, {:ok, result}, socket) do
    socket =
      case result do
        {:ok, result} ->
          # The refresh response carries last_processed_change_id but not
          # active_generation_refreshed_at -- re-fetch freshness for the
          # authoritative commit timestamp rather than approximating it.
          freshness = Ingestion.get_ingestion_freshness()

          socket
          |> assign(
            last_refresh_result: result,
            freshness: freshness,
            ingestion_refreshing: false,
            freshness_error: false
          )
          # docs/PRD.md § 7.6: clicking refresh must also refresh the
          # displayed opportunities, not just this timestamp -- otherwise
          # the table can keep showing rows computed from the previous
          # generation after the timestamp has already moved forward.
          |> load_opportunities()
          |> set_status_banner(ingestion_completion_message(result), @completion_banner_ms)

        {:error, _reason} ->
          # docs/PRD.md § 7.6: a failure keeps freshness_error as the sole
          # source of truth -- the banner is cleared, not repurposed to
          # report the failure too.
          socket
          |> assign(ingestion_refreshing: false, freshness_error: true)
          |> clear_status_banner()
      end

    {:noreply, socket}
  end

  def handle_async(:refresh_ingestion, {:exit, _reason}, socket) do
    socket =
      socket
      |> assign(ingestion_refreshing: false, freshness_error: true)
      |> clear_status_banner()

    {:noreply, socket}
  end

  defp load_opportunities(socket) do
    case socket.assigns.selected_league do
      nil ->
        assign(socket,
          opportunities: [],
          opportunities_loading: false,
          opportunities_error: false
        )

      league ->
        opportunities = FlipOpportunities.compute_flip_opportunities(league.external_id)

        assign(socket,
          opportunities: opportunities,
          opportunities_loading: false,
          opportunities_error: false
        )
    end
  end

  # Picks the current challenge league (is_current) if present, else the
  # first league in the list, else nil -- matches resolveDefaultLeagueId
  # from the React version's useLeagueSelection hook.
  defp resolve_default_league(leagues) do
    Enum.find(leagues, & &1.is_current) || List.first(leagues)
  end

  # Keeps the current selection if it still exists post-refresh (e.g. the
  # user picked Hardcore); only falls back to the default for a brand-new
  # list or one where the previously selected league disappeared.
  defp resolve_selected_league(leagues, current) do
    still_present? =
      current != nil and Enum.any?(leagues, &(&1.external_id == current.external_id))

    if still_present?,
      do: Enum.find(leagues, &(&1.external_id == current.external_id)),
      else: resolve_default_league(leagues)
  end

  defp flip_direction(:desc), do: :asc
  defp flip_direction(:asc), do: :desc

  defp toggle_set_membership(set, value) do
    if MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value)
  end

  defp parse_finite_number(value) do
    trimmed = String.trim(value)

    case Float.parse(trimmed) do
      {number, ""} -> {:ok, number}
      _ -> :error
    end
  end

  # Pushes the current filter/sort/threshold state down to the
  # DisplayPreferencesStorage JS hook to persist to localStorage -- called
  # after every change to any of the three, mirroring how favorites persist
  # on every toggle rather than only on unmount.
  defp persist_display_preferences(socket) do
    push_event(socket, "persist_display_preferences", %{
      active_tab: socket.assigns.active_tab,
      enabled_techniques: socket.assigns.enabled_techniques,
      enabled_categories: socket.assigns.enabled_categories,
      sort_column: socket.assigns.sort_column,
      sort_direction: socket.assigns.sort_direction,
      thresholds: socket.assigns.thresholds,
      max_start_chaos: socket.assigns.max_start_chaos
    })
  end

  defp parse_enabled_techniques(value, default) when is_map(value) do
    Map.new(@techniques, fn technique ->
      case Map.fetch(value, Atom.to_string(technique)) do
        {:ok, enabled} when is_boolean(enabled) -> {technique, enabled}
        _ -> {technique, Map.get(default, technique, true)}
      end
    end)
  end

  defp parse_enabled_techniques(_invalid, default), do: default

  defp parse_enabled_categories(value, default) when is_map(value) do
    Map.new(category_options(), fn {category, _label} ->
      case Map.fetch(value, Atom.to_string(category)) do
        {:ok, enabled} when is_boolean(enabled) -> {category, enabled}
        _ -> {category, Map.get(default, category, true)}
      end
    end)
  end

  defp parse_enabled_categories(_invalid, default), do: default

  defp parse_atom_in(value, allowed, default) when is_binary(value) do
    Enum.find(allowed, default, fn atom -> Atom.to_string(atom) == value end)
  end

  defp parse_atom_in(_invalid, _allowed, default), do: default

  defp parse_thresholds(value) when is_map(value) do
    Enum.reduce(@sort_columns, %{}, fn column, acc ->
      with raw when not is_nil(raw) <- Map.get(value, Atom.to_string(column)),
           {:ok, number} <- parse_finite_number(to_string(raw)) do
        Map.put(acc, column, number)
      else
        _ -> acc
      end
    end)
  end

  defp parse_thresholds(_invalid), do: %{}

  defp parse_max_start_chaos(value) when is_binary(value) or is_number(value) do
    case parse_finite_number(to_string(value)) do
      {:ok, number} -> number
      :error -> nil
    end
  end

  defp parse_max_start_chaos(_invalid), do: nil

  # docs/PRD.md § 7.6/7.7: token-based so a stale auto-dismiss timer from a
  # superseded banner (e.g. the in-flight message's own safety-net timer,
  # once the completion banner has already replaced it) becomes a no-op
  # instead of clobbering whatever is showing by the time it fires.
  defp set_status_banner(socket, message, duration_ms) do
    token = socket.assigns.status_banner_token + 1
    Process.send_after(self(), {:clear_status_banner, token}, duration_ms)

    assign(socket, status_banner: message, status_banner_token: token)
  end

  defp clear_status_banner(socket) do
    assign(socket,
      status_banner: nil,
      status_banner_token: socket.assigns.status_banner_token + 1
    )
  end

  # docs/PRD.md § 7.6: three distinct completion outcomes for an ingestion
  # refresh -- new data found, already caught up (with a computed ETA for
  # when new data will actually be available, not a guess), or partial
  # progress (the per-call hour cap was hit; another click continues).
  defp ingestion_completion_message(%{hours_processed: 0, fully_caught_up: true} = result) do
    "Already caught up · next data in #{format_eta(result.last_processed_change_id)}"
  end

  defp ingestion_completion_message(%{fully_caught_up: true} = result) do
    "Found new data (#{result.hours_processed}h processed)"
  end

  defp ingestion_completion_message(result) do
    "Partial progress (#{result.hours_processed}h) — refresh again to continue"
  end

  # GGG's Currency Exchange change-stream is bucketed one hour at a time,
  # and next_change_id is itself the literal hour-aligned Unix timestamp
  # (docs/DATA_SOURCES.md) -- so "when will new data exist" is simply that
  # checkpoint plus one bucket, compared against now, not a guess.
  defp format_eta(last_processed_change_id) do
    remaining_seconds =
      max(last_processed_change_id + @ingestion_bucket_seconds - System.system_time(:second), 0)

    case div(remaining_seconds, 60) do
      0 -> "under a minute"
      minutes -> "~#{minutes}m"
    end
  end

  defp catchup_cap_policy do
    config = Application.get_env(:poe_flip_finder, :ingestion, [])

    %PoeFlipFinder.CatchupCapPolicy{
      max_hours_per_call: Keyword.get(config, :max_hours_per_call, 48),
      first_run_lookback_hours: Keyword.get(config, :first_run_lookback_hours, 24)
    }
  end

  # Whole-number-valued input (the common case -- Left/Right are meant to
  # hold whole numbers per docs/PRD.md § 7.12) returns an integer, not a
  # float, so it displays as "145" rather than "145.0" when used directly
  # as a pair value in closest_ratio_matches/nearby_whole_ratio_suggestions
  # -- unlike JS's untyped numbers, Elixir's float-to-string always shows a
  # decimal point.
  defp parse_display_number(text) do
    case Float.parse(String.trim(text)) do
      {number, ""} when number == trunc(number) -> trunc(number)
      {number, ""} -> number
      _ -> nil
    end
  end

  defp technique_options do
    [
      {:vendor_recipe, "Vendor recipe", nil},
      {:exchange_spread, "Exchange spread", nil},
      {:divination_card, "Divination card", "divination-card-icon"},
      {:bulk_buy, "Bulk buy", nil}
    ]
  end

  # The tab bar above the results table (docs/PRD.md § 7.8): each tab
  # groups a subset of techniques, with per-technique checkboxes still
  # filtering within the active tab. "Historical Investment" has no
  # backing computation yet -- it renders as an inert, disabled tab (see
  # tab_disabled?/1) rather than a clickable one with nothing behind it.
  defp tab_options do
    [
      {:grand_exchange, "Grand Exchange Flip"},
      {:vendor, "Vendor Flip"},
      {:historical, "Historical Investment"}
    ]
  end

  defp tab_disabled?(:historical), do: true
  defp tab_disabled?(_tab), do: false

  defp techniques_for_tab(:grand_exchange), do: [:exchange_spread, :divination_card, :bulk_buy]
  defp techniques_for_tab(:vendor), do: [:vendor_recipe]
  defp techniques_for_tab(:historical), do: []

  defp technique_options_for_tab(tab) do
    allowed = techniques_for_tab(tab)
    Enum.filter(technique_options(), fn {technique, _label, _icon_class} -> technique in allowed end)
  end

  # A tab with only one technique has nothing to filter against itself --
  # showing a lone always-checked checkbox is pointless, so that tab skips
  # the filter-bar entirely and its technique is simply always on.
  defp show_technique_filters?(tab), do: length(techniques_for_tab(tab)) > 1

  # Scopes the technique checkboxes' own enabled/disabled state down to
  # whatever the active tab actually shows, without losing each checkbox's
  # remembered value when the user switches tabs and back. A tab with no
  # filter-bar of its own (see show_technique_filters?/1) forces its one
  # technique on, ignoring whatever was last persisted for it -- there's no
  # checkbox left to have stored a stale "off" value through, but a prior
  # session's saved preference could still have one, and it must not be
  # able to leave the technique permanently, invisibly disabled.
  defp effective_enabled_techniques(enabled_techniques, tab) do
    allowed = techniques_for_tab(tab)
    show_filters? = show_technique_filters?(tab)

    Map.new(enabled_techniques, fn {technique, enabled} ->
      cond do
        technique not in allowed -> {technique, false}
        show_filters? -> {technique, enabled}
        true -> {technique, true}
      end
    end)
  end

  # The Currency Category Filter drawer (docs/PRD.md § 7.13): one row per
  # group in the bundled Item Icons catalog (docs/DATA_SOURCES.md § Item
  # Icons), ordered by that catalog's own entry count, descending -- both
  # the menu order and the default `enabled_categories` map iterate this
  # same list, so there is exactly one place that knows the full category
  # set and its order.
  defp category_options do
    [
      {:cards, "Cards"},
      {:fragments, "Fragments, Scarabs & Mapping"},
      {:ancestor, "Tattoos & Omens"},
      {:essences, "Essences"},
      {:currency, "Currency"},
      {:beasts, "Beasts"},
      {:map_key, "Maps"},
      {:heist, "Heist Contracts & Blueprints"},
      {:runegrafts, "Runegrafts"},
      {:delve, "Fossils & Resonators"},
      {:sanctum, "Sanctum Tomes & Relics"},
      {:maps_unique, "Unique Maps"},
      {:delirium_orbs, "Delirium Orbs"},
      {:oils, "Oils & Extractor"},
      {:catalysts, "Catalysts"},
      {:ducats, "Ducats"},
      {:maps_special, "Shaper, Conqueror & Elder Maps"},
      {:allflame_embers, "Allflame Embers"},
      {:keepers, "Foulborn Currency & Wombgifts"},
      {:enshrouding_crystals, "Enshrouding Crystals"},
      {:legacy, "Legacy Items"},
      {:expedition, "Expedition Currency"},
      {:misc, "Misc"}
    ]
  end

  defp hamburger_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <line x1="4" y1="7" x2="20" y2="7" /><line x1="4" y1="12" x2="20" y2="12" />
      <line x1="4" y1="17" x2="20" y2="17" />
    </svg>
    """
  end

  attr :spinning, :boolean, required: true

  defp refresh_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      class={if @spinning, do: "league-refresh-button__icon--spinning"}
    >
      <polyline points="23 4 23 10 17 10" />
      <polyline points="1 20 1 14 7 14" />
      <path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15" />
    </svg>
    """
  end

  attr :technique, :atom, required: true
  attr :class, :string, default: nil

  defp technique_icon(%{technique: :vendor_recipe} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <circle cx="12" cy="8" r="4" /><path d="M4 21v-1a7 7 0 0 1 14 0v1" />
    </svg>
    """
  end

  defp technique_icon(%{technique: :exchange_spread} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M4 12h7M8 8l-4 4 4 4" /><path d="M20 12h-7M16 8l4 4-4 4" />
    </svg>
    """
  end

  defp technique_icon(%{technique: :divination_card} = assigns) do
    ~H"""
    <.divination_card_icon />
    """
  end

  defp technique_icon(%{technique: :bulk_buy} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M3 9l9-5 9 5-9 5-9-5z" /><path d="M3 9v6l9 5 9-5V9" /><path d="M12 14v6" />
    </svg>
    """
  end

  attr :category, :atom, required: true

  # One simple stroke-based line icon per category in the drawer (docs/PRD.md
  # § 7.13), same 24x24/stroke-only visual language as technique_icon/1
  # above -- generic line pictograms per category, not per-item artwork.
  defp category_icon(%{category: :cards} = assigns) do
    ~H"""
    <.divination_card_icon />
    """
  end

  defp category_icon(%{category: :fragments} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M12 2 4 12l8 10 8-10z" /><line x1="12" y1="2" x2="12" y2="22" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :ancestor} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M20 4c-5 0-14 3-14 12 0 2 1 4 3 4 9 0 12-9 12-14 0-1 0-2-1-2z" />
      <line x1="4" y1="20" x2="12" y2="12" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :essences} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M9 3h6M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3" />
      <line x1="8" y1="15" x2="16" y2="15" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :currency} = assigns) do
    ~H"""
    <.stroke_icon><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="4" /></.stroke_icon>
    """
  end

  defp category_icon(%{category: :beasts} = assigns) do
    ~H"""
    <.stroke_icon>
      <circle cx="7" cy="8" r="2" /><circle cx="12" cy="6" r="2" /><circle cx="17" cy="8" r="2" />
      <path d="M8 15c0-3 2-4 4-4s4 1 4 4-2 5-4 5-4-2-4-5z" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :map_key} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M12 21s7-6.5 7-12a7 7 0 0 0-14 0c0 5.5 7 12 7 12z" />
      <circle cx="12" cy="9" r="2.5" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :heist} = assigns) do
    ~H"""
    <.stroke_icon>
      <rect x="3" y="8" width="18" height="12" rx="2" />
      <path d="M8 8V6a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" /><line x1="3" y1="13" x2="21" y2="13" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :runegrafts} = assigns) do
    ~H"""
    <.stroke_icon><path d="M12 2 21 7v10l-9 5-9-5V7z" /></.stroke_icon>
    """
  end

  defp category_icon(%{category: :delve} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M6 10a2 2 0 1 0-3.5 1.3L7 15.8a2 2 0 1 0 2.8-2.8zM18 14a2 2 0 1 0 3.5-1.3L17 8.2a2 2 0 1 0-2.8 2.8z" />
      <line x1="8.5" y1="12.5" x2="15.5" y2="11.5" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :sanctum} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M4 5c3-1 6-1 8 0s5-1 8 0v14c-3-1-6-1-8 0s-5-1-8 0z" />
      <line x1="12" y1="5" x2="12" y2="19" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :maps_unique} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M12 2 3 9l9 13 9-13z" /><line x1="3" y1="9" x2="21" y2="9" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :delirium_orbs} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M8 12a4 4 0 1 1 8 0v4a4 4 0 0 1-8 0z" />
      <circle cx="10.5" cy="12" r="0.6" /><circle cx="13.5" cy="12" r="0.6" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :oils} = assigns) do
    ~H"""
    <.stroke_icon><path d="M12 3s7 8 7 13a7 7 0 1 1-14 0c0-5 7-13 7-13z" /></.stroke_icon>
    """
  end

  defp category_icon(%{category: :catalysts} = assigns) do
    ~H"""
    <.stroke_icon>
      <circle cx="12" cy="12" r="2" />
      <ellipse cx="12" cy="12" rx="9" ry="3.5" />
      <ellipse cx="12" cy="12" rx="9" ry="3.5" transform="rotate(60 12 12)" />
      <ellipse cx="12" cy="12" rx="9" ry="3.5" transform="rotate(120 12 12)" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :ducats} = assigns) do
    ~H"""
    <.stroke_icon><circle cx="12" cy="15" r="5" /><path d="M9 11 6 3M15 11l3-8" /></.stroke_icon>
    """
  end

  defp category_icon(%{category: :maps_special} = assigns) do
    ~H"""
    <.stroke_icon><path d="M4 18h16l-1-9-4 4-3-6-3 6-4-4z" /></.stroke_icon>
    """
  end

  defp category_icon(%{category: :allflame_embers} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M12 2c1 4-4 5-4 9a4 4 0 0 0 8 0c0-1-1-2-1-2 1 2 3 2 3 5a6 6 0 0 1-12 0C6 8 12 8 12 2z" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :keepers} = assigns) do
    ~H"""
    <.stroke_icon>
      <circle cx="12" cy="10" r="7" />
      <circle cx="9" cy="10" r="0.8" /><circle cx="15" cy="10" r="0.8" />
      <path d="M9 17v3M15 17v3M10 14h4" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :enshrouding_crystals} = assigns) do
    ~H"""
    <.stroke_icon>
      <path d="M8 2h8l4 7-8 13L4 9z" /><path d="M4 9h16M9 2l-1 7 4 13 4-13-1-7" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :legacy} = assigns) do
    ~H"""
    <.stroke_icon>
      <circle cx="12" cy="13" r="8" /><polyline points="12 9 12 13 15 15" />
      <path d="M4.5 6 3 3M8 3l-1 4" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :expedition} = assigns) do
    ~H"""
    <.stroke_icon>
      <circle cx="12" cy="12" r="9" /><polygon points="14.5 9.5 10 10 9.5 14.5 14 14 14.5 9.5" />
    </.stroke_icon>
    """
  end

  defp category_icon(%{category: :misc} = assigns) do
    ~H"""
    <.stroke_icon>
      <circle cx="6" cy="12" r="1.2" fill="currentColor" stroke="none" />
      <circle cx="12" cy="12" r="1.2" fill="currentColor" stroke="none" />
      <circle cx="18" cy="12" r="1.2" fill="currentColor" stroke="none" />
    </.stroke_icon>
    """
  end

  slot :inner_block, required: true

  defp stroke_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      {render_slot(@inner_block)}
    </svg>
    """
  end

  attr :column, :atom, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :sort_column, :atom, required: true
  attr :sort_direction, :atom, required: true
  attr :threshold_value, :any, required: true

  defp sortable_column_header(assigns) do
    is_active = assigns.sort_column == assigns.column
    assigns = assign(assigns, :is_active, is_active)

    ~H"""
    <div class="col-head">
      <span
        class={"col-label#{if @is_active, do: " active"}"}
        phx-click="toggle_sort"
        phx-value-column={@column}
      >
        {@label} <.sort_arrow_icon direction={if @is_active, do: @sort_direction} />
      </span>
      <form phx-change="set_threshold" phx-submit="set_threshold" phx-value-column={@column}>
        <input
          class="col-filter"
          type="number"
          placeholder={@placeholder}
          value={@threshold_value}
          phx-debounce="150"
          name="value"
        />
      </form>
    </div>
    """
  end

  attr :max_start_chaos, :any, required: true

  # Filter-only, not sortable -- Start isn't a sortable column, so this
  # deliberately doesn't reuse sortable_column_header/1 above (no
  # phx-click="toggle_sort", no sort arrow). Centered (col-head--center)
  # to match Start's own centered cells, unlike Margin/Profit/Volume's
  # right-aligned numbers.
  defp start_column_header(assigns) do
    ~H"""
    <div class="col-head col-head--center">
      <span style="text-align: center">Start</span>
      <form phx-change="set_max_start" phx-submit="set_max_start">
        <input
          class="col-filter"
          type="number"
          placeholder="max c"
          value={@max_start_chaos}
          phx-debounce="150"
          name="value"
        />
      </form>
    </div>
    """
  end

  attr :direction, :atom, default: nil

  defp sort_arrow_icon(%{direction: :asc} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      width="11"
      height="11"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M12 19V5M5 12l7-7 7 7" />
    </svg>
    """
  end

  defp sort_arrow_icon(%{direction: :desc} = assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      width="11"
      height="11"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M12 5v14M5 12l7 7 7-7" />
    </svg>
    """
  end

  defp sort_arrow_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      width="11"
      height="11"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M8 9l4-4 4 4M8 15l4 4 4-4" />
    </svg>
    """
  end

  attr :opportunity, :any, required: true
  attr :favorite?, :boolean, required: true

  defp flip_row(assigns) do
    margin =
      PoeFlipFinder.FlipOpportunityPresenter.format_margin(assigns.opportunity.margin_percent)

    profit =
      PoeFlipFinder.FlipOpportunityPresenter.format_profit(
        assigns.opportunity.profit.quantity,
        assigns.opportunity.margin_percent
      )

    route_key = PoeFlipFinder.FlipOpportunityTablePresenter.get_route_key(assigns.opportunity)
    assigns = assign(assigns, margin: margin, profit: profit, route_key: route_key)

    ~H"""
    <div
      class={"grid row#{if @favorite?, do: " fav"}"}
      data-route-key={@route_key}
      phx-hook="RowContextMenu"
      id={"row-#{@route_key}"}
    >
      <span :if={@favorite?} class="fav-star" aria-hidden="true"><.star_icon /></span>
      <.currency_cell amount={hd(@opportunity.start)} />
      <div>
        <div class="via-icons">
          <%= for {amount, index} <- Enum.with_index(@opportunity.via) do %>
            <span :if={index > 0} class="arrow" aria-hidden="true">&#8594;</span>
            <span class="qty">
              {PoeFlipFinder.FlipOpportunityPresenter.format_quantity(amount.quantity)}
            </span>
            <.currency_icon amount={amount} />
            {amount.currency.display_name}
          <% end %>
        </div>
        <div class="sub">{@opportunity.detail}</div>
      </div>
      <.currency_cell amount={hd(@opportunity.sell)} />
      <div class={"margin #{@margin.color_class}"}>{@margin.text}</div>
      <div class={"profit #{@profit.color_class}"}>
        {@profit.text}
        <.currency_icon amount={@opportunity.profit} />
      </div>
      <div class="vol">
        {PoeFlipFinder.FlipOpportunityPresenter.format_volume(@opportunity.volume)}
      </div>
    </div>
    """
  end

  attr :amount, :any, required: true

  defp currency_cell(assigns) do
    ~H"""
    <div class="cur">
      <div class="cur-top">
        <span class="qty">
          {PoeFlipFinder.FlipOpportunityPresenter.format_quantity(@amount.quantity)}
        </span>
        <.currency_icon amount={@amount} />
      </div>
      {@amount.currency.display_name}
    </div>
    """
  end

  attr :amount, :any, required: true

  # Divination cards have no real icon from GGG's Item Icons data (their
  # icon_url is always nil -- see docs/DATA_SOURCES.md), so they always
  # render the generic card-suit glyph instead, per TECH_STACK.md.
  defp currency_icon(%{amount: %{currency: %{category: :cards}}} = assigns) do
    ~H"""
    <.divination_card_icon />
    """
  end

  defp currency_icon(%{amount: %{currency: %{icon_url: nil}}} = assigns) do
    ~H""
  end

  defp currency_icon(assigns) do
    ~H"""
    <img src={@amount.currency.icon_url} alt="" />
    """
  end

  defp divination_card_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="#c98ded"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
      class="divination-card-icon"
    >
      <rect x="4" y="6" width="12" height="16" rx="2" transform="rotate(-8 10 14)" />
      <rect x="9" y="4" width="12" height="16" rx="2" transform="rotate(8 15 12)" />
    </svg>
    """
  end

  defp star_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor" aria-hidden="true">
      <path d="M12 2l2.9 6.6 7.1.6-5.4 4.7 1.6 7-6.2-3.8L5.8 21l1.6-7L2 9.2l7.1-.6z" />
    </svg>
    """
  end

  defp calculator_icon(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <rect x="4" y="2" width="16" height="20" rx="2" />
      <line x1="8" y1="6" x2="16" y2="6" />
      <line x1="8" y1="11" x2="8" y2="11.01" />
      <line x1="12" y1="11" x2="12" y2="11.01" />
      <line x1="16" y1="11" x2="16" y2="11.01" />
      <line x1="8" y1="15" x2="8" y2="15.01" />
      <line x1="12" y1="15" x2="12" y2="15.01" />
      <line x1="16" y1="15" x2="16" y2="15.01" />
      <line x1="8" y1="19" x2="16" y2="19" />
    </svg>
    """
  end
end
