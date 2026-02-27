defmodule Syncal.Admin do
  def admin?(name) when is_binary(name) do
    normalized = name |> String.trim() |> String.downcase()
    admin_names() |> Enum.any?(&(String.downcase(&1) == normalized))
  end
  def admin?(_), do: false

  def display_name(name) do
    normalized = name |> String.trim() |> String.downcase()
    case Enum.find_index(admin_names(), &(String.downcase(&1) == normalized)) do
      nil -> name
      idx -> Enum.at(display_names(), idx, name)
    end
  end

  defp admin_names do
    System.get_env("ADMIN_USERS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp display_names do
    System.get_env("ADMIN_USERS_DISPLAY_NAMES", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
  end
end
