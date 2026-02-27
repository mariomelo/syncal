defmodule Syncal.Availability.Slot do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "availability_slots" do
    field :date, :date
    field :start_minutes, :integer
    field :end_minutes, :integer
    belongs_to :participant, Syncal.Participants.Participant
    belongs_to :inquiry, Syncal.Inquiries.Inquiry

    timestamps(type: :utc_datetime)
  end

  def changeset(slot, attrs) do
    slot
    |> cast(attrs, [:date, :start_minutes, :end_minutes, :participant_id, :inquiry_id])
    |> validate_required([:date, :start_minutes, :end_minutes, :participant_id, :inquiry_id])
    |> validate_number(:start_minutes, greater_than_or_equal_to: 0, less_than: 1440)
    |> validate_number(:end_minutes, greater_than: 0, less_than_or_equal_to: 1440)
    |> validate_time_range()
  end

  defp validate_time_range(changeset) do
    s = get_field(changeset, :start_minutes)
    e = get_field(changeset, :end_minutes)
    if s && e && s >= e, do: add_error(changeset, :end_minutes, "must be after start time"), else: changeset
  end
end
