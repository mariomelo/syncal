defmodule SyncalWeb.CalendarLive do
  use SyncalWeb, :live_component

  @month_names ~w(January February March April May June July August September October November December)

  def mount(socket) do
    {:ok, assign(socket, current_month: nil)}
  end

  def update(assigns, socket) do
    selected_date = Map.get(assigns, :selected_date)

    current_month =
      socket.assigns[:current_month] ||
        case selected_date do
          %Date{} = d -> {d.year, d.month}
          _ -> {assigns.min_date.year, assigns.min_date.month}
        end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:current_month, current_month)
     |> assign_new(:selected_dates, fn -> [] end)
     |> assign_new(:select_event, fn -> "select_date" end)
     |> assign_new(:excluded_dates, fn -> [] end)}
  end

  def handle_event("prev_month", _, socket) do
    {year, month} = socket.assigns.current_month
    {:noreply, assign(socket, :current_month, prev_month(year, month))}
  end

  def handle_event("next_month", _, socket) do
    {year, month} = socket.assigns.current_month
    {:noreply, assign(socket, :current_month, next_month(year, month))}
  end

  def render(assigns) do
    {year, month} = assigns.current_month
    today = Date.utc_today()
    days = calendar_days(year, month)
    {can_prev, can_next} = nav_allowed(year, month, assigns.min_date, assigns.max_date)
    month_label = "#{Enum.at(@month_names, month - 1)} #{year}"
    slot_set = MapSet.new(assigns.my_slot_dates)
    multi_set = MapSet.new(assigns.selected_dates)
    excluded_set = MapSet.new(assigns.excluded_dates)

    assigns =
      assign(assigns,
        days: days,
        today: today,
        can_prev: can_prev,
        can_next: can_next,
        month_label: month_label,
        slot_set: slot_set,
        multi_set: multi_set,
        excluded_set: excluded_set
      )

    ~H"""
    <div>
      <div class="flex items-center justify-between mb-3">
        <button
          type="button"
          phx-click="prev_month"
          phx-target={@myself}
          disabled={!@can_prev}
          class="btn btn-ghost btn-sm btn-square disabled:opacity-30"
        >
          <svg viewBox="0 0 20 20" fill="currentColor" class="size-5" aria-hidden="true">
            <path fill-rule="evenodd" clip-rule="evenodd" d="M11.78 5.22a.75.75 0 0 1 0 1.06L8.06 10l3.72 3.72a.75.75 0 1 1-1.06 1.06l-4.25-4.25a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Z" />
          </svg>
        </button>
        <span class="text-sm font-semibold"><%= @month_label %></span>
        <button
          type="button"
          phx-click="next_month"
          phx-target={@myself}
          disabled={!@can_next}
          class="btn btn-ghost btn-sm btn-square disabled:opacity-30"
        >
          <svg viewBox="0 0 20 20" fill="currentColor" class="size-5" aria-hidden="true">
            <path fill-rule="evenodd" clip-rule="evenodd" d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z" />
          </svg>
        </button>
      </div>

      <div class="grid grid-cols-7 text-center text-xs text-base-content/50 mb-1">
        <div>Mo</div><div>Tu</div><div>We</div><div>Th</div><div>Fr</div><div>Sa</div><div>Su</div>
      </div>

      <div class="grid grid-cols-7">
        <%= for {{date, kind}, idx} <- Enum.with_index(@days) do %>
          <% is_first_row = idx < 7 %>
          <% is_current_month = kind == :current %>
          <% is_today = date == @today %>
          <% in_range = Date.compare(date, @min_date) != :lt && Date.compare(date, @max_date) != :gt %>
          <% is_excluded = MapSet.member?(@excluded_set, date) %>
          <% is_clickable = in_range && !is_excluded %>
          <% is_single_selected = !is_nil(@selected_date) && date == @selected_date %>
          <% is_multi_selected = MapSet.member?(@multi_set, date) %>
          <% has_slots = MapSet.member?(@slot_set, Date.to_iso8601(date)) %>
          <% state = day_state(in_range, is_excluded, is_single_selected, is_multi_selected, is_today, is_current_month) %>
          <div class={["flex flex-col items-center py-1", !is_first_row && "border-t border-base-300"]}>
            <button
              type="button"
              phx-click={is_clickable && @select_event}
              phx-value-date={Date.to_iso8601(date)}
              disabled={!is_clickable}
              class={[
                "size-8 flex items-center justify-center rounded-full text-sm leading-none",
                day_class(state)
              ]}
            >
              <time datetime={Date.to_iso8601(date)}><%= date.day %></time>
            </button>
            <span class={["w-1.5 h-1.5 rounded-full mt-0.5", dot_class(has_slots, is_single_selected || is_multi_selected)]}></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Day state — order matters: first match wins
  defp day_state(false, _, _, _, _, _), do: :disabled
  defp day_state(_, true, _, _, _, _), do: :excluded
  defp day_state(_, _, true, _, _, _), do: :single_selected
  defp day_state(_, _, _, true, _, _), do: :multi_selected
  defp day_state(_, _, _, _, true, _), do: :today
  defp day_state(_, _, _, _, _, true), do: :current
  defp day_state(_, _, _, _, _, _), do: :other

  defp day_class(:disabled), do: "text-base-content/20 cursor-not-allowed"
  defp day_class(:excluded), do: "ring-2 ring-inset ring-primary/50 text-primary/50 font-semibold cursor-not-allowed"
  defp day_class(:single_selected), do: "bg-primary text-primary-content font-semibold"
  defp day_class(:multi_selected), do: "bg-accent text-accent-content font-semibold"
  defp day_class(:today), do: "text-primary font-semibold hover:bg-base-200 cursor-pointer"
  defp day_class(:current), do: "text-base-content hover:bg-base-200 cursor-pointer"
  defp day_class(:other), do: "text-base-content/40 hover:bg-base-200 cursor-pointer"

  # Green dot: visible when has slots and not selected (selected circle already stands out)
  defp dot_class(true, false), do: "bg-success"
  defp dot_class(_, _), do: "invisible"

  defp prev_month(year, 1), do: {year - 1, 12}
  defp prev_month(year, month), do: {year, month - 1}

  defp next_month(year, 12), do: {year + 1, 1}
  defp next_month(year, month), do: {year, month + 1}

  defp nav_allowed(year, month, min_date, max_date) do
    can_prev = year > min_date.year || (year == min_date.year && month > min_date.month)
    can_next = year < max_date.year || (year == max_date.year && month < max_date.month)
    {can_prev, can_next}
  end

  defp calendar_days(year, month) do
    first_day = Date.new!(year, month, 1)
    days_in_month = Date.days_in_month(first_day)

    # Elixir: Monday = 1, so offset = day_of_week - 1 (Mon = col 0)
    start_offset = Date.day_of_week(first_day) - 1

    {prev_year, prev_month_num} = prev_month(year, month)
    prev_days_in_month = Date.days_in_month(Date.new!(prev_year, prev_month_num, 1))

    prev_padding =
      if start_offset > 0 do
        Enum.map(
          (prev_days_in_month - start_offset + 1)..prev_days_in_month//1,
          fn d -> {Date.new!(prev_year, prev_month_num, d), :other} end
        )
      else
        []
      end

    current_days =
      Enum.map(1..days_in_month//1, fn d -> {Date.new!(year, month, d), :current} end)

    combined = prev_padding ++ current_days

    next_fill =
      case rem(length(combined), 7) do
        0 -> 0
        r -> 7 - r
      end

    {next_year, next_month_num} = next_month(year, month)

    next_padding =
      if next_fill > 0 do
        Enum.map(1..next_fill//1, fn d -> {Date.new!(next_year, next_month_num, d), :other} end)
      else
        []
      end

    combined ++ next_padding
  end
end
