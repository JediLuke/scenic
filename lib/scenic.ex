defmodule Scenic do
  @moduledoc """
  The Scenic module itself is a supervisor that manages all the machinery that
  makes the [Scenes](overview_scene.html), [ViewPorts](overview_viewport.html),
  and [Drivers](overview_driver.html) run.

  In order to run any Scenic application, you will need to start the Scenic
  supervisor in your supervision tree.

  Load a configuration for one or more ViewPorts, then add Scenic to your root
  supervisor.

      defmodule MyApp do

        def start(_type, _args) do
          import Supervisor.Spec, warn: false

          # load the viewport configuration from config
          main_viewport_config = Application.get_env(:my_app :viewport)

          # start the application with the viewport
          children = [
            supervisor(Scenic, [viewports: [main_viewport_config]]),
          ]
          Supervisor.start_link(children, strategy: :one_for_one)
        end

      end

  Note that you can start the Scenic supervisor without any ViewPort
  Configurations. In that case, you are responsible for supervising
  the ViewPorts yourself. This is not recommended for devices
  as Scenic should know how to restart the main ViewPort in the event
  of an error.
  """

  use Supervisor

  @viewports :scenic_viewports
  @version Mix.Project.config()[:version]

  @doc """
  Return the current version of scenic
  """
  def version(), do: @version

  # --------------------------------------------------------
  @doc false
  def child_spec(vp_opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [vp_opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: 500
    }
  end

  # --------------------------------------------------------
  @doc false
  def start_link(vps \\ [])

  def start_link(vps) when is_list(vps) do
    case Supervisor.start_link(__MODULE__, nil, name: :scenic) do
      {:ok, pid} ->
        # start the default ViewPort
        Enum.each(vps, &Scenic.ViewPort.start(&1))

        # return the original start_link value
        {:ok, pid}

      error ->
        error
    end
  end

  # --------------------------------------------------------
  @doc false
  def init(_) do
    [
      Scenic.PubSub,
      Scenic.Assets.Stream,
      {DynamicSupervisor, name: @viewports, strategy: :one_for_one}
    ]
    |> Supervisor.init(strategy: :one_for_one)
  end

  # =========================================================================
  # Developer Tools - Convenience delegates
  
  @doc """
  Display semantic information for the current viewport.
  
  Convenience function that delegates to `Scenic.DevTools.semantic/2`.
  
  ## Examples
  
      iex> Scenic.semantic()
      === Semantic Tree for :main ===
      Total elements: 3
      ...
  """
  defdelegate semantic(viewport_name \\ :main_viewport, graph_key \\ :main), 
    to: Scenic.DevTools
  
  @doc """
  Show all text buffers and their content.
  
  Convenience function that delegates to `Scenic.DevTools.buffers/2`.
  
  ## Examples
  
      iex> Scenic.buffers()
      Text Buffers:
      [1] "Hello, World!"
      ...
  """
  defdelegate buffers(viewport_name \\ :main_viewport, graph_key \\ :main), 
    to: Scenic.DevTools
    
  @doc """
  Show content of a specific buffer.
  
  Convenience function that delegates to `Scenic.DevTools.buffer/3`.
  
  ## Examples
  
      iex> Scenic.buffer(1)
      Buffer 1:
      Hello, World!
  """
  defdelegate buffer(buffer_id, viewport_name \\ :main_viewport, graph_key \\ :main), 
    to: Scenic.DevTools
    
  @doc """
  Show all buttons in the viewport.
  
  Convenience function that delegates to `Scenic.DevTools.buttons/2`.
  
  ## Examples
  
      iex> Scenic.buttons()
      Buttons:
      - "Save" (id: :save_btn)
      ...
  """
  defdelegate buttons(viewport_name \\ :main_viewport, graph_key \\ :main), 
    to: Scenic.DevTools
    
  @doc """
  Find elements by semantic type.
  
  Convenience function that delegates to `Scenic.DevTools.find/3`.
  
  ## Examples
  
      iex> Scenic.find(:menu)
      Found 1 menu element(s):
      - :main_menu: %{type: :menu, name: "File"}
  """
  defdelegate find(type, viewport_name \\ :main_viewport, graph_key \\ :main), 
    to: Scenic.DevTools
    
  @doc """
  List all semantic types in use.
  
  Convenience function that delegates to `Scenic.DevTools.types/2`.
  
  ## Examples
  
      iex> Scenic.types()
      Semantic types in use:
      - button (2 elements)
      - text_buffer (1 element)
  """
  defdelegate types(viewport_name \\ :main_viewport, graph_key \\ :main), 
    to: Scenic.DevTools
end
