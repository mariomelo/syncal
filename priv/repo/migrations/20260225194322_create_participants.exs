defmodule Syncal.Repo.Migrations.CreateParticipants do
  use Ecto.Migration

  def change do
    create table(:participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :name_normalized, :string, null: false
      add :timezone, :string, null: false, default: "UTC"
      add :inquiry_id, references(:inquiries, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:participants, [:inquiry_id])
    create unique_index(:participants, [:name_normalized, :inquiry_id])
  end
end
