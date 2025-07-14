defmodule Scenic.DevTools do
  @moduledoc """
  Developer tools for inspecting Scenic applications during development.
  
  Import this module in your IEx session for easy access to semantic
  inspection and debugging tools.
  
  ## Usage in IEx
  
      iex> import Scenic.DevTools
      iex> semantic()              # Show semantic info for default viewport
      iex> semantic(:my_viewport)  # Show semantic info for named viewport
      iex> buffers()               # Show all text buffers
      iex> buttons()               # Show all buttons
  """
  
  alias Scenic.{ViewPort, Semantic}
  alias Scenic.Semantic.Query
  
  @doc """
  Display semantic information for the current viewport.
  
  ## Examples
  
      iex> semantic()
      === Semantic Tree for :main ===
      Total elements: 3
      
      By type:
        text_buffer: 1 element
          - :buffer_1: %{type: :text_buffer, buffer_id: 1}
        button: 2 elements
          - :save_btn: %{type: :button, label: "Save"}
          - :cancel_btn: %{type: :button, label: "Cancel"}
  """
  def semantic(viewport_name \\ :main_viewport, graph_key \\ :main) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      ViewPort.inspect_semantic(viewport, graph_key)
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Show all text buffers and their content.
  
  ## Examples
  
      iex> buffers()
      Text Buffers:
      [1] "Hello, World!"
      [2] "def my_function do\\n  :ok\\nend"
  """
  def buffers(viewport_name \\ :main_viewport, graph_key \\ :main) do
    with {:ok, viewport} <- get_viewport(viewport_name),
         {:ok, buffers} <- Query.find_by_type(viewport, :text_buffer, graph_key) do
      IO.puts("Text Buffers:")
      Enum.each(buffers, fn buffer ->
        content = buffer.content || ""
        buffer_id = buffer.semantic.buffer_id
        preview = String.slice(content, 0, 60)
        preview = if String.length(content) > 60, do: preview <> "...", else: preview
        IO.puts("[#{buffer_id}] #{inspect(preview)}")
      end)
      :ok
    else
      {:error, :not_found} -> 
        IO.puts("No text buffers found")
        :ok
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Show content of a specific buffer.
  
  ## Examples
  
      iex> buffer(1)
      Buffer 1:
      Hello, World!
  """
  def buffer(buffer_id, viewport_name \\ :main_viewport, graph_key \\ :main) do
    with {:ok, viewport} <- get_viewport(viewport_name),
         {:ok, content} <- Query.get_buffer_text(viewport, buffer_id, graph_key) do
      IO.puts("Buffer #{buffer_id}:")
      IO.puts(content)
      :ok
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Show all buttons in the viewport.
  
  ## Examples
  
      iex> buttons()
      Buttons:
      - "Save" (id: :save_btn)
      - "Cancel" (id: :cancel_btn)
  """
  def buttons(viewport_name \\ :main_viewport, graph_key \\ :main) do
    with {:ok, viewport} <- get_viewport(viewport_name),
         {:ok, buttons} <- Query.get_buttons(viewport, graph_key) do
      IO.puts("Buttons:")
      Enum.each(buttons, fn button ->
        label = button.semantic.label
        id = button.id
        IO.puts("- #{inspect(label)} (id: #{inspect(id)})")
      end)
      :ok
    else
      {:error, :not_found} -> 
        IO.puts("No buttons found")
        :ok
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Find elements by semantic type.
  
  ## Examples
  
      iex> find(:menu)
      Found 1 menu element(s):
      - :main_menu: %{type: :menu, name: "File"}
  """
  def find(type, viewport_name \\ :main_viewport, graph_key \\ :main) do
    with {:ok, viewport} <- get_viewport(viewport_name),
         {:ok, elements} <- Query.find_by_type(viewport, type, graph_key) do
      IO.puts("Found #{length(elements)} #{type} element(s):")
      Enum.each(elements, fn elem ->
        IO.puts("- #{inspect(elem.id)}: #{inspect(elem.semantic)}")
      end)
      :ok
    else
      {:error, :not_found} -> 
        IO.puts("No #{type} elements found")
        :ok
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Get raw semantic data for a viewport.
  
  ## Examples
  
      iex> raw_semantic()
      %{
        elements: %{...},
        by_type: %{...},
        timestamp: 1234567890
      }
  """
  def raw_semantic(viewport_name \\ :main_viewport, graph_key \\ :main) do
    with {:ok, viewport} <- get_viewport(viewport_name),
         {:ok, info} <- ViewPort.get_semantic(viewport, graph_key) do
      info
    else
      error -> error
    end
  end
  
  @doc """
  List all semantic types in use.
  
  ## Examples
  
      iex> types()
      Semantic types in use:
      - button (2 elements)
      - text_buffer (1 element)
      - menu (1 element)
  """
  def types(viewport_name \\ :main_viewport, graph_key \\ :main) do
    with {:ok, viewport} <- get_viewport(viewport_name),
         {:ok, info} <- ViewPort.get_semantic(viewport, graph_key) do
      IO.puts("Semantic types in use:")
      info.by_type
      |> Enum.sort_by(fn {_type, ids} -> -length(ids) end)
      |> Enum.each(fn {type, ids} ->
        count = length(ids)
        element_word = if count == 1, do: "element", else: "elements"
        IO.puts("- #{type} (#{count} #{element_word})")
      end)
      :ok
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  # Private helpers
  
  defp get_viewport(viewport) when is_struct(viewport, ViewPort), do: {:ok, viewport}
  defp get_viewport(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, "ViewPort #{inspect(name)} not found"}
      pid -> ViewPort.info(pid)
    end
  end
  defp get_viewport(pid) when is_pid(pid), do: ViewPort.info(pid)
end