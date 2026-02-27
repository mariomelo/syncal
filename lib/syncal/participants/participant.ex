defmodule Syncal.Participants.Participant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "participants" do
    field :name, :string
    field :name_normalized, :string
    field :timezone, :string, default: "UTC"
    belongs_to :inquiry, Syncal.Inquiries.Inquiry
    has_many :availability_slots, Syncal.Availability.Slot

    timestamps(type: :utc_datetime)
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:name, :timezone, :inquiry_id])
    |> validate_required([:name, :inquiry_id])
    |> validate_length(:name, min: 1, max: 100)
    |> put_name_normalized()
    |> unique_constraint([:name_normalized, :inquiry_id], message: "already joined this inquiry")
  end

  def timezone_changeset(participant, attrs) do
    participant
    |> cast(attrs, [:timezone])
    |> validate_required([:timezone])
  end

  defp put_name_normalized(changeset) do
    case get_change(changeset, :name) do
      nil -> changeset
      name -> put_change(changeset, :name_normalized, name |> String.trim() |> String.downcase())
    end
  end
end
