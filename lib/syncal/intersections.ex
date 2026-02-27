defmodule Syncal.Intersections do
  @doc """
  Given a list of slots (each with preloaded :participant), computes
  all time segments where 2+ participants are simultaneously available.
  Returns a list of maps: %{start_dt: DateTime, end_dt: DateTime, duration_minutes: integer, participants: [Participant]}
  sorted by duration desc.
  """
  def compute(slots) do
    # Convert each slot to UTC interval + participant
    intervals =
      slots
      |> Enum.flat_map(fn slot ->
        tz = slot.participant.timezone
        with {:ok, start_dt} <- to_utc(slot.date, slot.start_minutes, tz),
             {:ok, end_dt} <- to_utc(slot.date, slot.end_minutes, tz) do
          [{start_dt, end_dt, slot.participant}]
        else
          _ -> []
        end
      end)

    if Enum.empty?(intervals), do: [], else: sweep(intervals)
  end

  defp to_utc(date, minutes, timezone) do
    h = div(minutes, 60)
    m = rem(minutes, 60)
    with {:ok, time} <- Time.new(h, m, 0),
         {:ok, naive} <- NaiveDateTime.new(date, time),
         {:ok, dt} <- DateTime.from_naive(naive, timezone) do
      {:ok, DateTime.shift_zone!(dt, "UTC")}
    end
  end

  defp sweep(intervals) do
    # Create events: {:start, time, participant} and {:end, time, participant}
    events =
      Enum.flat_map(intervals, fn {start_dt, end_dt, participant} ->
        [{start_dt, :start, participant}, {end_dt, :end, participant}]
      end)
      |> Enum.sort_by(fn {dt, type, _} ->
        # Sort by time, end before start at same time (to avoid zero-length segments)
        {DateTime.to_unix(dt, :microsecond), if(type == :end, do: 0, else: 1)}
      end)

    {segments, _, _} =
      Enum.reduce(events, {[], nil, []}, fn {time, type, participant}, {segs, prev_time, active} ->
        new_segs =
          if prev_time && DateTime.compare(prev_time, time) != :eq && length(active) >= 2 do
            duration = div(DateTime.diff(time, prev_time), 60)
            if duration > 0 do
              [%{start_dt: prev_time, end_dt: time, duration_minutes: duration, participants: active} | segs]
            else
              segs
            end
          else
            segs
          end

        new_active =
          case type do
            :start -> [participant | active]
            :end -> Enum.reject(active, &(&1.id == participant.id))
          end

        {new_segs, time, new_active}
      end)

    segments
    |> Enum.sort_by(& &1.duration_minutes, :desc)
  end

  @doc "Filter intersections by minimum duration and minimum participant count"
  def filter(intersections, min_duration_minutes \\ 0, min_participants \\ 2) do
    intersections
    |> Enum.filter(fn i ->
      i.duration_minutes >= min_duration_minutes and
        length(i.participants) >= min_participants
    end)
  end
end
