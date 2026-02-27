defmodule SyncalWeb.InquiryLive do
  use SyncalWeb, :live_view

  alias Syncal.{Admin, Inquiries, Participants, Availability, Intersections}
  alias Syncal.Participants.Participant

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Inquiries.get_inquiry(id) do
      nil ->
        {:ok, push_navigate(socket, to: "/")}
      inquiry ->
        participants = Participants.list_by_inquiry(inquiry.id)
        slots = Availability.get_all_slots_for_inquiry(inquiry.id)
        intersections = Intersections.compute(slots)
        dates = Inquiries.date_range(inquiry)

        {:ok, assign(socket,
          page_title: inquiry.title,
          inquiry: inquiry,
          participants: participants,
          all_slots: slots,
          intersections: intersections,
          dates: dates,
          current_participant: nil,
          name_input: "",
          is_admin: false,
          timezone: "UTC",
          selected_date: List.first(dates),
          day_slots: [],
          my_slot_dates: [],
          replicate_targets: [],
          show_replicate: false,
          min_duration: 0,
          min_participants: 2,
          show_mode: "all",
          error: nil,
          join_error: nil
        )}
    end
  end

  # ── Session ──────────────────────────────────────────────────────────────

  @impl true
  # Has a valid stored participant ID — try to match it to this inquiry
  def handle_event("restore_session", %{"name" => name, "participant_id" => pid}, socket)
      when name != "" and pid != "" do
    case Participants.get_participant(pid) do
      %Participant{inquiry_id: iid} = p when iid == socket.assigns.inquiry.id ->
        {:noreply, do_join(socket, p)}
      _ ->
        # Participant ID belongs to a different inquiry (e.g. admin navigating here) — join by name
        join_by_name(socket, name)
    end
  end

  # No participant ID stored (e.g. admin coming from home dashboard) — join by name
  def handle_event("restore_session", %{"name" => name}, socket) when name != "" do
    join_by_name(socket, name)
  end

  def handle_event("restore_session", _, socket), do: {:noreply, socket}

  def handle_event("logout", _, socket) do
    {:noreply,
      socket
      |> assign(current_participant: nil, name_input: "", is_admin: false,
                 day_slots: [], my_slot_dates: [], timezone: "UTC")
      |> push_event("clear_user", %{})}
  end

  # ── Timezone ─────────────────────────────────────────────────────────────

  def handle_event("detect_timezone", %{"timezone" => tz}, socket) do
    if is_nil(socket.assigns.current_participant) do
      {:noreply, assign(socket, timezone: tz)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("update_timezone", %{"timezone" => tz}, socket) do
    socket = assign(socket, timezone: tz)
    socket =
      case socket.assigns.current_participant do
        nil -> socket
        p ->
          case Participants.update_timezone(p, tz) do
            {:ok, updated} -> assign(socket, current_participant: updated)
            {:error, _} -> socket
          end
      end
    {:noreply, socket}
  end

  # ── Join ─────────────────────────────────────────────────────────────────

  def handle_event("set_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, name_input: name, join_error: nil)}
  end

  def handle_event("join", %{"name" => name}, socket) do
    name = String.trim(name)
    if name == "" do
      {:noreply, assign(socket, join_error: "Please enter your name")}
    else
      case Participants.get_or_create(name, socket.assigns.inquiry.id, socket.assigns.timezone) do
        {:ok, participant} ->
          {:noreply,
            socket
            |> assign(join_error: nil)
            |> do_join(participant)
            |> push_event("store_user", %{name: participant.name, participant_id: participant.id})}
        {:error, changeset} ->
          err = changeset.errors |> Enum.map(fn {k, {m, _}} -> "#{k}: #{m}" end) |> Enum.join(", ")
          {:noreply, assign(socket, join_error: err)}
      end
    end
  end

  # ── Date selection ────────────────────────────────────────────────────────

  def handle_event("select_date", %{"date" => date_str}, socket) do
    case Date.from_iso8601(date_str) do
      {:ok, date} ->
        day_slots =
          case socket.assigns.current_participant do
            nil -> []
            p -> Availability.get_slots_by_date(p.id, socket.assigns.inquiry.id, date)
          end
        {:noreply, assign(socket, selected_date: date, day_slots: day_slots, show_replicate: false)}
      _ ->
        {:noreply, socket}
    end
  end

  # ── Availability ──────────────────────────────────────────────────────────

  def handle_event("add_slot", %{"start" => start_str, "end" => end_str}, socket) do
    with %Participant{} = p <- socket.assigns.current_participant,
         {:ok, start_m} <- parse_time(start_str),
         {:ok, end_m} <- parse_time(end_str),
         true <- end_m > start_m do
      existing = Enum.map(socket.assigns.day_slots, &%{start_minutes: &1.start_minutes, end_minutes: &1.end_minutes})
      case Availability.set_slots_for_day(p.id, socket.assigns.inquiry.id, socket.assigns.selected_date,
             existing ++ [%{start_minutes: start_m, end_minutes: end_m}]) do
        {:ok, _} -> {:noreply, reload_slots(socket)}
        _ -> {:noreply, assign(socket, error: "Failed to save slot")}
      end
    else
      nil -> {:noreply, socket}
      _ -> {:noreply, assign(socket, error: "End time must be after start time")}
    end
  end

  def handle_event("remove_slot", %{"id" => slot_id}, socket) do
    p = socket.assigns.current_participant
    new_slots =
      socket.assigns.day_slots
      |> Enum.reject(&(&1.id == slot_id))
      |> Enum.map(&%{start_minutes: &1.start_minutes, end_minutes: &1.end_minutes})
    case Availability.set_slots_for_day(p.id, socket.assigns.inquiry.id, socket.assigns.selected_date, new_slots) do
      {:ok, _} -> {:noreply, reload_slots(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_replicate", _, socket) do
    {:noreply, assign(socket, show_replicate: !socket.assigns.show_replicate, replicate_targets: [])}
  end

  def handle_event("toggle_replicate_target", %{"date" => date_str}, socket) do
    date = Date.from_iso8601!(date_str)
    targets = socket.assigns.replicate_targets
    new_targets =
      if Enum.member?(targets, date),
        do: Enum.reject(targets, &(&1 == date)),
        else: [date | targets]
    {:noreply, assign(socket, replicate_targets: new_targets)}
  end

  def handle_event("replicate", _, socket) do
    p = socket.assigns.current_participant
    case Availability.replicate_day(p.id, socket.assigns.inquiry.id,
           socket.assigns.selected_date, socket.assigns.replicate_targets) do
      {:ok, _} ->
        {:noreply, socket |> reload_slots() |> assign(show_replicate: false, replicate_targets: [], error: nil)}
      _ ->
        {:noreply, assign(socket, error: "Failed to replicate")}
    end
  end

  # ── Dashboard filters ─────────────────────────────────────────────────────
  # All three filters are sent together via a single phx-change form

  def handle_event("filter_changed", params, socket) do
    {:noreply, assign(socket,
      min_duration: String.to_integer(params["min_duration"] || "0"),
      min_participants: String.to_integer(params["min_participants"] || "2"),
      show_mode: params["show_mode"] || "all"
    )}
  end

  # ── Admin ─────────────────────────────────────────────────────────────────

  def handle_event("remove_participant", %{"id" => participant_id}, socket) do
    if socket.assigns.is_admin do
      case Participants.get_participant(participant_id) do
        nil -> {:noreply, socket}
        p ->
          Participants.remove_participant(p)
          {:noreply, reload_slots(socket)}
      end
    else
      {:noreply, socket}
    end
  end

  # ── Private helpers ────────────────────────────────────────────────────────

  defp join_by_name(socket, name) do
    inquiry = socket.assigns.inquiry
    timezone = socket.assigns.timezone
    case Participants.get_or_create(name, inquiry.id, timezone) do
      {:ok, p} ->
        {:noreply,
          socket
          |> do_join(p)
          |> push_event("store_user", %{name: p.name, participant_id: p.id})}
      _ ->
        {:noreply, socket}
    end
  end

  defp do_join(socket, %Participant{} = p) do
    inquiry = socket.assigns.inquiry
    day_slots = Availability.get_slots_by_date(p.id, inquiry.id, socket.assigns.selected_date)
    all_slots = Availability.get_all_slots_for_inquiry(inquiry.id)
    intersections = Intersections.compute(all_slots)
    participants = Participants.list_by_inquiry(inquiry.id)
    my_slot_dates = compute_my_slot_dates(all_slots, p)

    assign(socket,
      current_participant: p,
      name_input: p.name,
      is_admin: Admin.admin?(p.name),
      timezone: p.timezone,
      day_slots: day_slots,
      all_slots: all_slots,
      intersections: intersections,
      participants: participants,
      my_slot_dates: my_slot_dates
    )
  end

  defp reload_slots(socket) do
    inquiry = socket.assigns.inquiry
    p = socket.assigns.current_participant
    all_slots = Availability.get_all_slots_for_inquiry(inquiry.id)
    day_slots =
      if p, do: Availability.get_slots_by_date(p.id, inquiry.id, socket.assigns.selected_date), else: []
    intersections = Intersections.compute(all_slots)
    participants = Participants.list_by_inquiry(inquiry.id)
    my_slot_dates = compute_my_slot_dates(all_slots, p)

    assign(socket,
      all_slots: all_slots,
      day_slots: day_slots,
      intersections: intersections,
      participants: participants,
      my_slot_dates: my_slot_dates,
      error: nil
    )
  end

  defp compute_my_slot_dates(_slots, nil), do: []
  defp compute_my_slot_dates(slots, %{id: pid}) do
    slots
    |> Enum.filter(&(&1.participant_id == pid))
    |> Enum.map(&Date.to_iso8601(&1.date))
    |> Enum.uniq()
  end

  defp parse_time(str) do
    case String.split(str, ":") do
      [h, m] ->
        with {h_int, ""} <- Integer.parse(h),
             {m_int, ""} <- Integer.parse(m),
             true <- h_int in 0..23,
             true <- m_int in 0..59 do
          {:ok, h_int * 60 + m_int}
        else
          _ -> :error
        end
      _ -> :error
    end
  end

  defp format_minutes(minutes) do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    "#{String.pad_leading(to_string(h), 2, "0")}:#{String.pad_leading(to_string(m), 2, "0")}"
  end

  defp format_duration(minutes) do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    cond do
      h > 0 and m > 0 -> "#{h}h #{m}m"
      h > 0 -> "#{h}h"
      true -> "#{m}m"
    end
  end

  # Format a UTC DateTime into the user's chosen timezone, showing the UTC offset
  defp format_dt_in_tz(%DateTime{} = dt, timezone) do
    require Logger
    result = case DateTime.shift_zone(dt, timezone) do
      {:ok, local} ->
        Calendar.strftime(local, "%b %d, %H:%M") <> " (#{utc_offset_label(timezone)})"
      {:error, reason} ->
        Logger.warning("[TZ] shift_zone FAILED tz=#{inspect(timezone)} reason=#{inspect(reason)}")
        Calendar.strftime(dt, "%b %d, %H:%M (UTC)")
    end
    Logger.warning("[TZ] format_dt_in_tz tz=#{timezone} => #{result}")
    result
  end

  defp format_time_in_tz(%DateTime{} = dt, timezone) do
    case DateTime.shift_zone(dt, timezone) do
      {:ok, local} -> Calendar.strftime(local, "%H:%M")
      _ -> Calendar.strftime(dt, "%H:%M")
    end
  end

  # Returns "UTC+2" / "UTC-3" etc. for the current moment in the given timezone
  defp utc_offset_label(timezone) do
    case DateTime.now(timezone) do
      {:ok, dt} ->
        total = dt.utc_offset + dt.std_offset
        h = div(abs(total), 3600)
        m = rem(div(abs(total), 60), 60)
        sign = if total >= 0, do: "+", else: "-"
        if m == 0,
          do: "UTC#{sign}#{h}",
          else: "UTC#{sign}#{h}:#{String.pad_leading(to_string(m), 2, "0")}"
      _ -> "UTC"
    end
  end

  # Returns [{tz_id, "City (UTC+X)"}, ...]
  defp tz_options do
    [
      {"UTC",                                "UTC"},
      {"America/Los_Angeles",                "Los Angeles"},
      {"America/Denver",                     "Denver"},
      {"America/Chicago",                    "Chicago / Texas"},
      {"America/Indiana/Indianapolis",       "Indiana"},
      {"America/New_York",                   "New York"},
      {"America/Edmonton",                   "Calgary"},
      {"America/Sao_Paulo",                  "São Paulo"},
      {"America/Argentina/Buenos_Aires",     "Buenos Aires"},
      {"Europe/Lisbon",                      "Lisbon"},
      {"Europe/London",                      "London"},
      {"Europe/Amsterdam",                   "Amsterdam"},
      {"Europe/Paris",                       "Paris"},
      {"Europe/Rome",                        "Bologna / Rome"},
      {"Europe/Berlin",                      "Berlin / Hamburg"},
      {"Europe/Moscow",                      "Moscow"},
      {"Asia/Dubai",                         "Dubai"},
      {"Asia/Kolkata",                       "Bangalore / Kolkata"},
      {"Asia/Shanghai",                      "Shanghai"},
      {"Asia/Singapore",                     "Singapore"},
      {"Asia/Tokyo",                         "Tokyo"},
      {"Australia/Sydney",                   "Sydney"},
      {"Pacific/Auckland",                   "Auckland"},
    ]
    |> Enum.map(fn {tz_id, city} ->
      label = "#{city} (#{utc_offset_label(tz_id)})"
      {tz_id, label}
    end)
  end

  @impl true
  def render(assigns) do
    tz_opts = tz_options()

    # Apply all three filters
    filtered =
      assigns.intersections
      |> Intersections.filter(assigns.min_duration, assigns.min_participants)
      |> filter_by_show_mode(assigns.show_mode, assigns.current_participant)

    assigns = assign(assigns, filtered_intersections: filtered, tz_opts: tz_opts)

    ~H"""
    <div id="inquiry-page" phx-hook="TimezoneDetect">
      <div id="restore-hook" phx-hook="RestoreSession" style="display:none"></div>

      <div class="navbar bg-base-100 shadow-sm px-4">
        <div class="flex-1 gap-2 min-w-0">
          <a href="/" class="text-xl font-bold shrink-0">Syncal</a>
          <span class="text-base-content/30 shrink-0">/</span>
          <span class="text-sm font-medium truncate"><%= @inquiry.title %></span>
        </div>
        <div class="flex-none gap-2 items-center">
          <%= if @current_participant do %>
            <span class="badge badge-primary hidden sm:inline-flex"><%= @current_participant.name %></span>
            <button class="btn btn-ghost btn-xs" phx-click="logout">Logout</button>
          <% end %>
        </div>
      </div>

      <div class="container mx-auto p-4 max-w-6xl">
        <p class="text-base-content/50 text-sm mb-4">
          <%= Calendar.strftime(@inquiry.start_date, "%B %d") %> –
          <%= Calendar.strftime(@inquiry.end_date, "%B %d, %Y") %>
        </p>

        <%!-- Join form --%>
        <%= if is_nil(@current_participant) do %>
          <div class="card bg-base-100 shadow mb-6 max-w-md">
            <div class="card-body">
              <h2 class="card-title text-base">Join this inquiry</h2>
              <form phx-submit="join" class="flex gap-2">
                <input type="text" name="name" placeholder="Your name"
                  class="input input-bordered flex-1" value={@name_input} required autofocus />
                <button type="submit" class="btn btn-primary">Join</button>
              </form>
              <%= if @join_error do %>
                <div class="alert alert-error py-2 text-sm mt-1"><span><%= @join_error %></span></div>
              <% end %>
            </div>
          </div>
        <% end %>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Left: calendar + editor --%>
          <div class="flex flex-col gap-4">

            <%!-- Calendar card --%>
            <div class="card bg-base-100 shadow">
              <div class="card-body pb-3">
                <div class="flex justify-between items-center mb-2 gap-2 flex-wrap">
                  <h2 class="card-title text-base shrink-0">Select a day</h2>
                  <%= if @current_participant do %>
                    <form phx-change="update_timezone">
                      <select class="select select-xs select-bordered max-w-[220px]" name="timezone">
                        <%= for {tz_id, label} <- @tz_opts do %>
                          <option value={tz_id} selected={tz_id == @timezone}><%= label %></option>
                        <% end %>
                      </select>
                    </form>
                  <% end %>
                </div>

                <.live_component
                  module={SyncalWeb.CalendarLive}
                  id={"calendar-#{@inquiry.id}"}
                  selected_date={@selected_date}
                  min_date={hd(@dates)}
                  max_date={List.last(@dates)}
                  my_slot_dates={@my_slot_dates}
                />
                <%= if @current_participant && length(@my_slot_dates) > 0 do %>
                  <p class="text-xs text-base-content/40 mt-1">
                    Days with a green dot already have your availability.
                  </p>
                <% end %>
              </div>
            </div>

            <%!-- Availability editor --%>
            <%= if @current_participant do %>
              <div class="card bg-base-100 shadow">
                <div class="card-body">
                  <h2 class="card-title text-base">
                    <%= Calendar.strftime(@selected_date, "%A, %B %d") %>
                  </h2>

                  <%= if Enum.empty?(@day_slots) do %>
                    <p class="text-base-content/40 text-sm">No availability set for this day.</p>
                  <% else %>
                    <div class="flex flex-col gap-1">
                      <%= for slot <- @day_slots do %>
                        <div class="flex items-center justify-between bg-success/10 rounded-lg px-3 py-2">
                          <span class="font-mono text-sm">
                            <%= format_minutes(slot.start_minutes) %> – <%= format_minutes(slot.end_minutes) %>
                          </span>
                          <button class="btn btn-ghost btn-xs text-error"
                            phx-click="remove_slot" phx-value-id={slot.id}>✕</button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <form phx-submit="add_slot" class="flex gap-2 mt-2 items-end">
                    <div class="form-control flex-1">
                      <label class="label py-0"><span class="label-text text-xs">From</span></label>
                      <input type="time" name="start" class="input input-bordered input-sm" value="09:00" required />
                    </div>
                    <div class="form-control flex-1">
                      <label class="label py-0"><span class="label-text text-xs">To</span></label>
                      <input type="time" name="end" class="input input-bordered input-sm" value="17:00" required />
                    </div>
                    <button type="submit" class="btn btn-success btn-sm">Add</button>
                  </form>

                  <%= if @error do %>
                    <div class="alert alert-error py-2 text-sm"><span><%= @error %></span></div>
                  <% end %>

                  <div class="mt-3">
                    <button class="btn btn-outline btn-xs" phx-click="toggle_replicate">
                      <%= if @show_replicate, do: "Cancel", else: "Copy to other days…" %>
                    </button>
                    <%= if @show_replicate do %>
                      <div class="mt-2">
                        <p class="text-xs text-base-content/60 mb-2">Select days to copy this schedule to:</p>
                        <.live_component
                          module={SyncalWeb.CalendarLive}
                          id={"replicate-calendar-#{@inquiry.id}"}
                          selected_date={@selected_date}
                          excluded_dates={[@selected_date]}
                          selected_dates={@replicate_targets}
                          select_event="toggle_replicate_target"
                          min_date={hd(@dates)}
                          max_date={List.last(@dates)}
                          my_slot_dates={@my_slot_dates}
                        />
                        <%= if length(@replicate_targets) > 0 do %>
                          <button class="btn btn-accent btn-sm mt-3" phx-click="replicate">
                            Copy to <%= length(@replicate_targets) %> day(s)
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                </div>
              </div>
            <% end %>

            <%!-- Participants --%>
            <div class="card bg-base-100 shadow">
              <div class="card-body py-3">
                <h2 class="card-title text-sm text-base-content/60">
                  Participants (<%= length(@participants) %>)
                </h2>
                <div class="flex flex-col gap-1">
                  <%= for p <- @participants do %>
                    <div class="flex items-center justify-between">
                      <span class="text-sm"><%= p.name %></span>
                      <%= if @is_admin && @current_participant && p.id != @current_participant.id do %>
                        <button class="btn btn-ghost btn-xs text-error"
                          phx-click="remove_participant" phx-value-id={p.id}>Remove</button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <%!-- Right: intersections dashboard --%>
          <div>
            <div class="card bg-base-100 shadow">
              <div class="card-body">
                <div class="flex justify-between items-start">
                  <h2 class="card-title text-base">Available Slots</h2>
                  <%= if @current_participant do %>
                    <span class="text-xs text-base-content/40 mt-1">
                      Showing in <strong><%= utc_offset_label(@timezone) %></strong>
                    </span>
                  <% end %>
                </div>

                <%!-- All three filters in one form so phx-change reliably sends all values --%>
                <form phx-change="filter_changed" class="flex gap-3 flex-wrap">
                  <div class="form-control">
                    <label class="label py-0"><span class="label-text text-xs">Min duration</span></label>
                    <select class="select select-sm select-bordered" name="min_duration">
                      <option value="0" selected={@min_duration == 0}>Any</option>
                      <option value="30" selected={@min_duration == 30}>30 min</option>
                      <option value="60" selected={@min_duration == 60}>1 hour</option>
                      <option value="90" selected={@min_duration == 90}>90 min</option>
                      <option value="120" selected={@min_duration == 120}>2 hours</option>
                      <option value="180" selected={@min_duration == 180}>3 hours</option>
                    </select>
                  </div>
                  <div class="form-control">
                    <label class="label py-0"><span class="label-text text-xs">Min participants</span></label>
                    <select class="select select-sm select-bordered" name="min_participants">
                      <%= for n <- 2..max(2, length(@participants)) do %>
                        <option value={n} selected={n == @min_participants}><%= n %> people</option>
                      <% end %>
                    </select>
                  </div>
                  <div class="form-control">
                    <label class="label py-0"><span class="label-text text-xs">View</span></label>
                    <select class="select select-sm select-bordered" name="show_mode">
                      <option value="all" selected={@show_mode == "all"}>All intersections</option>
                      <option value="mine" selected={@show_mode == "mine"} disabled={is_nil(@current_participant)}>
                        My intersections
                      </option>
                    </select>
                  </div>
                </form>

                <div class="flex flex-col gap-2 mt-3">
                  <%= if Enum.empty?(@filtered_intersections) do %>
                    <div class="text-center py-10 text-base-content/40">
                      <p class="text-3xl mb-2">🤔</p>
                      <p>No common slots found yet.</p>
                      <p class="text-xs mt-1">Add availability or adjust filters.</p>
                    </div>
                  <% else %>
                    <%= for i <- @filtered_intersections do %>
                      <div class="border border-base-300 rounded-lg p-3">
                        <div class="flex justify-between items-start gap-2">
                          <div>
                            <p class="font-semibold text-sm">
                              <%= format_dt_in_tz(i.start_dt, @timezone) %>
                            </p>
                            <p class="text-xs text-base-content/50">
                              until <%= format_time_in_tz(i.end_dt, @timezone) %>
                            </p>
                          </div>
                          <div class="text-right shrink-0">
                            <span class="badge badge-success badge-sm"><%= format_duration(i.duration_minutes) %></span>
                            <br/>
                            <span class="badge badge-ghost badge-sm mt-1"><%= length(i.participants) %> people</span>
                          </div>
                        </div>
                        <div class="flex flex-wrap gap-1 mt-2">
                          <%= for p <- i.participants do %>
                            <span class={"badge badge-sm #{if @current_participant && p.id == @current_participant.id, do: "badge-primary", else: "badge-ghost"}"}>
                              <%= p.name %>
                            </span>
                          <% end %>
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp filter_by_show_mode(intersections, "mine", %{id: pid}) do
    Enum.filter(intersections, fn i -> Enum.any?(i.participants, &(&1.id == pid)) end)
  end
  defp filter_by_show_mode(intersections, _, _), do: intersections
end
