defmodule Syncal.Inquiries do
  import Ecto.Query
  alias Syncal.Repo
  alias Syncal.Inquiries.Inquiry

  def list_inquiries do
    Repo.all(from i in Inquiry, order_by: [desc: i.inserted_at])
  end

  def list_inquiries_with_stats do
    Repo.all(
      from i in Inquiry,
        left_join: p in assoc(i, :participants),
        left_join: s in assoc(p, :availability_slots),
        group_by: i.id,
        order_by: [desc: i.inserted_at],
        select: %{
          id: i.id,
          title: i.title,
          start_date: i.start_date,
          end_date: i.end_date,
          inserted_at: i.inserted_at,
          participant_count: count(p.id, :distinct),
          slot_count: count(s.id, :distinct)
        }
    )
  end

  def get_inquiry(id) do
    Repo.get(Inquiry, id)
  end

  def get_inquiry_with_participants(id) do
    Inquiry
    |> Repo.get(id)
    |> Repo.preload(participants: [:availability_slots])
  end

  def create_inquiry(attrs) do
    %Inquiry{}
    |> Inquiry.changeset(attrs)
    |> Repo.insert()
  end

  def date_range(%Inquiry{start_date: s, end_date: e}) do
    Date.range(s, e) |> Enum.to_list()
  end
end
