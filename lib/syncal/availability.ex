defmodule Syncal.Availability do
  import Ecto.Query
  alias Syncal.Repo
  alias Syncal.Availability.Slot

  def get_slots_for_participant(participant_id, inquiry_id) do
    Repo.all(
      from s in Slot,
        where: s.participant_id == ^participant_id and s.inquiry_id == ^inquiry_id,
        order_by: [asc: s.date, asc: s.start_minutes]
    )
  end

  def get_slots_by_date(participant_id, inquiry_id, date) do
    Repo.all(
      from s in Slot,
        where: s.participant_id == ^participant_id and s.inquiry_id == ^inquiry_id and s.date == ^date,
        order_by: s.start_minutes
    )
  end

  def set_slots_for_day(participant_id, inquiry_id, date, slots_attrs) do
    Repo.transaction(fn ->
      Repo.delete_all(
        from s in Slot,
          where: s.participant_id == ^participant_id and s.inquiry_id == ^inquiry_id and s.date == ^date
      )
      Enum.each(slots_attrs, fn attrs ->
        %Slot{}
        |> Slot.changeset(Map.merge(attrs, %{
          participant_id: participant_id,
          inquiry_id: inquiry_id,
          date: date
        }))
        |> Repo.insert!()
      end)
    end)
  end

  def replicate_day(participant_id, inquiry_id, source_date, target_dates) do
    source_slots = get_slots_by_date(participant_id, inquiry_id, source_date)
    Repo.transaction(fn ->
      Enum.each(target_dates, fn target_date ->
        Repo.delete_all(
          from s in Slot,
            where: s.participant_id == ^participant_id and s.inquiry_id == ^inquiry_id and s.date == ^target_date
        )
        Enum.each(source_slots, fn slot ->
          %Slot{}
          |> Slot.changeset(%{
            date: target_date,
            start_minutes: slot.start_minutes,
            end_minutes: slot.end_minutes,
            participant_id: participant_id,
            inquiry_id: inquiry_id
          })
          |> Repo.insert!()
        end)
      end)
    end)
  end

  def get_all_slots_for_inquiry(inquiry_id) do
    Repo.all(
      from s in Slot,
        where: s.inquiry_id == ^inquiry_id,
        join: p in assoc(s, :participant),
        preload: [participant: p],
        order_by: [asc: s.date, asc: s.start_minutes]
    )
  end
end
