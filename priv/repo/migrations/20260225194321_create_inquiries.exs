defmodule Syncal.Repo.Migrations.CreateInquiries do
  use Ecto.Migration

  def change do
    create table(:inquiries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :start_date, :date, null: false
      add :end_date, :date, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
