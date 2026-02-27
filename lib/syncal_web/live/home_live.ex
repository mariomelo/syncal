defmodule SyncalWeb.HomeLive do
  use SyncalWeb, :live_view

  alias Syncal.{Admin, Inquiries}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      page_title: "Syncal",
      name: "",
      is_admin: false,
      name_confirmed: false,
      inquiries: [],
      show_new_form: false,
      form_error: nil,
      error: nil
    )}
  end

  @impl true
  def handle_event("set_name", %{"name" => name}, socket) do
    {:noreply, assign(socket, name: name, error: nil)}
  end

  def handle_event("confirm_name", %{"name" => name}, socket) do
    name = String.trim(name)
    if name == "" do
      {:noreply, assign(socket, error: "Please enter your name")}
    else
      login(socket, name)
    end
  end

  def handle_event("restore_session", %{"name" => name}, socket) when name != "" do
    if Admin.admin?(name) do
      login(socket, name)
    else
      {:noreply, socket}
    end
  end
  def handle_event("restore_session", _, socket), do: {:noreply, socket}

  def handle_event("logout", _, socket) do
    {:noreply,
      socket
      |> assign(name: "", is_admin: false, name_confirmed: false, inquiries: [])
      |> push_event("clear_user", %{})}
  end

  def handle_event("toggle_new_form", _, socket) do
    {:noreply, assign(socket, show_new_form: !socket.assigns.show_new_form, form_error: nil)}
  end

  def handle_event("create_inquiry", %{"title" => title, "start_date" => start_date, "end_date" => end_date}, socket) do
    attrs = %{
      title: String.trim(title),
      start_date: parse_date(start_date),
      end_date: parse_date(end_date)
    }
    case Inquiries.create_inquiry(attrs) do
      {:ok, _inquiry} ->
        inquiries = Inquiries.list_inquiries_with_stats()
        {:noreply, assign(socket, inquiries: inquiries, show_new_form: false, form_error: nil)}
      {:error, changeset} ->
        errors = changeset.errors |> Enum.map(fn {k, {msg, _}} -> "#{k} #{msg}" end) |> Enum.join(", ")
        {:noreply, assign(socket, form_error: errors)}
    end
  end

  defp login(socket, name) do
    is_admin = Admin.admin?(name)
    inquiries = if is_admin, do: Inquiries.list_inquiries_with_stats(), else: []
    socket =
      socket
      |> assign(name: name, is_admin: is_admin, name_confirmed: true, inquiries: inquiries, error: nil)
    # Persist admin name so they don't have to type it again
    socket = if is_admin, do: push_event(socket, "store_user", %{name: name, participant_id: ""}), else: socket
    {:noreply, socket}
  end

  defp parse_date(""), do: nil
  defp parse_date(str) do
    case Date.from_iso8601(str) do
      {:ok, d} -> d
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="home-page" phx-hook="RestoreSession">
      <%= if @name_confirmed and @is_admin do %>
        <%!-- Admin Dashboard --%>
        <div class="min-h-screen bg-base-200">
          <div class="navbar bg-base-100 shadow-sm px-6">
            <div class="flex-1">
              <span class="text-xl font-bold">Syncal</span>
            </div>
            <div class="flex-none gap-3 items-center">
              <span class="text-sm text-base-content/60">Admin</span>
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content rounded-full w-9">
                  <span class="text-sm font-bold"><%= String.upcase(String.first(@name)) %></span>
                </div>
              </div>
              <span class="font-semibold text-sm"><%= Admin.display_name(@name) %></span>
              <button class="btn btn-ghost btn-sm" phx-click="logout">Logout</button>
            </div>
          </div>

          <div class="container mx-auto p-6 max-w-5xl">
            <div class="stats stats-horizontal shadow bg-base-100 w-full mb-6">
              <div class="stat">
                <div class="stat-title">Total Inquiries</div>
                <div class="stat-value text-primary"><%= length(@inquiries) %></div>
              </div>
              <div class="stat">
                <div class="stat-title">Total Participants</div>
                <div class="stat-value text-secondary">
                  <%= @inquiries |> Enum.map(& &1.participant_count) |> Enum.sum() %>
                </div>
              </div>
              <div class="stat">
                <div class="stat-title">Availability Slots</div>
                <div class="stat-value">
                  <%= @inquiries |> Enum.map(& &1.slot_count) |> Enum.sum() %>
                </div>
              </div>
            </div>

            <div class="flex justify-between items-center mb-4">
              <h2 class="text-xl font-bold">Inquiries</h2>
              <button class="btn btn-primary btn-sm" phx-click="toggle_new_form">
                <%= if @show_new_form, do: "Cancel", else: "+ New Inquiry" %>
              </button>
            </div>

            <%= if @show_new_form do %>
              <div class="card bg-base-100 shadow mb-6">
                <div class="card-body">
                  <h3 class="card-title text-base">New Inquiry</h3>
                  <form phx-submit="create_inquiry">
                    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div class="form-control md:col-span-3">
                        <label class="label"><span class="label-text">Title</span></label>
                        <input type="text" name="title" placeholder="e.g. Team meeting Q1"
                          class="input input-bordered" autofocus required />
                      </div>
                      <div class="form-control">
                        <label class="label"><span class="label-text">Start date</span></label>
                        <input type="date" name="start_date" class="input input-bordered" required />
                      </div>
                      <div class="form-control">
                        <label class="label"><span class="label-text">End date</span></label>
                        <input type="date" name="end_date" class="input input-bordered" required />
                      </div>
                      <div class="flex items-end">
                        <button type="submit" class="btn btn-success w-full">Create</button>
                      </div>
                    </div>
                    <%= if @form_error do %>
                      <div class="alert alert-error mt-3 py-2 text-sm"><span><%= @form_error %></span></div>
                    <% end %>
                  </form>
                </div>
              </div>
            <% end %>

            <%= if Enum.empty?(@inquiries) do %>
              <div class="card bg-base-100 shadow">
                <div class="card-body text-center py-16 text-base-content/50">
                  <p class="text-4xl mb-3">📋</p>
                  <p class="font-semibold">No inquiries yet</p>
                  <p class="text-sm">Click <strong>+ New Inquiry</strong> to create your first one.</p>
                </div>
              </div>
            <% else %>
              <div class="flex flex-col gap-3">
                <%= for inquiry <- @inquiries do %>
                  <div class="card bg-base-100 shadow hover:shadow-md transition-shadow">
                    <div class="card-body py-4 px-5">
                      <div class="flex items-start justify-between gap-4">
                        <div class="flex-1 min-w-0">
                          <a href={"/" <> inquiry.id} class="text-lg font-semibold hover:text-primary transition-colors">
                            <%= inquiry.title %>
                          </a>
                          <p class="text-sm text-base-content/60 mt-0.5">
                            <%= Calendar.strftime(inquiry.start_date, "%b %d") %> –
                            <%= Calendar.strftime(inquiry.end_date, "%b %d, %Y") %>
                            · <%= Date.diff(inquiry.end_date, inquiry.start_date) + 1 %> days
                          </p>
                          <p class="text-xs text-base-content/40 font-mono mt-1 truncate">
                            <%= "#{SyncalWeb.Endpoint.url()}/#{inquiry.id}" %>
                          </p>
                        </div>
                        <div class="flex gap-2 items-center shrink-0">
                          <div class="badge badge-ghost gap-1">
                            <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z" />
                            </svg>
                            <%= inquiry.participant_count %>
                          </div>
                          <a href={"/" <> inquiry.id} class="btn btn-sm btn-outline btn-primary">Open</a>
                        </div>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        </div>

      <% else %>
        <%!-- Login / Landing --%>
        <div class="min-h-screen bg-base-200 flex flex-col items-center justify-center p-4">
          <div class="card w-full max-w-md bg-base-100 shadow-xl">
            <div class="card-body gap-4">
              <div class="text-center">
                <h1 class="text-3xl font-bold">Syncal</h1>
                <p class="text-base-content/60 text-sm mt-1">Find a time that works for everyone</p>
              </div>

              <form phx-submit="confirm_name" class="form-control gap-3">
                <div>
                  <label class="label pb-1"><span class="label-text font-medium">Your name</span></label>
                  <input type="text" placeholder="Enter your name..." class="input input-bordered w-full"
                    value={@name} phx-change="set_name" name="name" phx-debounce="200" autofocus />
                </div>
                <button type="submit" class="btn btn-primary w-full">Continue</button>
              </form>

              <%= if @error do %>
                <div class="alert alert-error py-2 text-sm"><span><%= @error %></span></div>
              <% end %>

              <%= if @name_confirmed and not @is_admin do %>
                <div class="alert alert-info py-3 text-sm">
                  <div>
                    <p>Hi, <strong><%= @name %></strong>!</p>
                    <p class="mt-1 opacity-80">You need an inquiry link to fill in your availability. Ask your admin to share one.</p>
                    <%= if System.get_env("ADMIN_USERS", "") == "" do %>
                      <p class="text-xs mt-2 opacity-60">
                        Dev tip: set <code class="font-mono">ADMIN_USERS=<%= @name %></code> in <code>.env</code>
                      </p>
                    <% end %>
                  </div>
                </div>
              <% end %>

              <div class="divider text-xs text-base-content/40 my-0">or</div>
              <p class="text-center text-xs text-base-content/50">
                Already have an inquiry link? Paste it in the address bar.
              </p>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
