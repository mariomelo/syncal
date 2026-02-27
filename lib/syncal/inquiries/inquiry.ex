defmodule Syncal.Inquiries.Inquiry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "inquiries" do
    field :title, :string
    field :start_date, :date
    field :end_date, :date

    has_many :participants, Syncal.Participants.Participant
    has_many :availability_slots, Syncal.Availability.Slot

    timestamps(type: :utc_datetime)
  end

  def changeset(inquiry, attrs) do
    inquiry
    |> cast(attrs, [:title, :start_date, :end_date])
    |> validate_required([:title, :start_date, :end_date])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_date_order()
  end

  defp validate_date_order(changeset) do
    start_date = get_field(changeset, :start_date)
    end_date = get_field(changeset, :end_date)
    if start_date && end_date && Date.compare(start_date, end_date) == :gt do
      add_error(changeset, :end_date, "must be on or after start date")
    else
      changeset
    end
  end
end
