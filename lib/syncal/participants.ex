defmodule Syncal.Participants do
  import Ecto.Query
  alias Syncal.Repo
  alias Syncal.Participants.Participant

  def get_or_create(name, inquiry_id, timezone \\ "UTC") do
    normalized = name |> String.trim() |> String.downcase()
    case Repo.get_by(Participant, name_normalized: normalized, inquiry_id: inquiry_id) do
      nil ->
        %Participant{}
        |> Participant.changeset(%{name: name, inquiry_id: inquiry_id, timezone: timezone})
        |> Repo.insert()
      participant -> {:ok, participant}
    end
  end

  def get_participant(id), do: Repo.get(Participant, id)

  def update_timezone(participant, timezone) do
    participant
    |> Participant.timezone_changeset(%{timezone: timezone})
    |> Repo.update()
  end

  def remove_participant(participant) do
    Repo.delete(participant)
  end

  def list_by_inquiry(inquiry_id) do
    Repo.all(from p in Participant, where: p.inquiry_id == ^inquiry_id, order_by: p.name)
  end
end
