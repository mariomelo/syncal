defmodule Syncal.Repo do
  use Ecto.Repo,
    otp_app: :syncal,
    adapter: Ecto.Adapters.Postgres
end
