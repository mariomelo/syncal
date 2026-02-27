defmodule Syncal.Repo.Migrations.CreateAvailabilitySlots do
  use Ecto.Migration

  def change do
    create table(:availability_slots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :date, :date, null: false
      # stored as minutes since midnight UTC for simplicity
      add :start_minutes, :integer, null: false
      add :end_minutes, :integer, null: false
      add :participant_id, references(:participants, type: :binary_id, on_delete: :delete_all), null: false
      add :inquiry_id, references(:inquiries, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:availability_slots, [:participant_id])
    create index(:availability_slots, [:inquiry_id])
    create index(:availability_slots, [:inquiry_id, :date])
  end
end
