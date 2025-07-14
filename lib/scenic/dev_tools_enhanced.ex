defmodule Scenic.DevToolsEnhanced do
  @moduledoc """
  Enhanced developer tools that work with UUID graph keys.
  
  This module extends the basic DevTools to handle cases where
  graph keys are UUIDs rather than simple atoms.
  """
  
  alias Scenic.ViewPort
  
  @doc """
  Display all semantic information across all graphs.
  """
  def semantic_all(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Filter to only entries with semantic data
      semantic_entries = Enum.filter(entries, fn {_key, data} ->
        map_size(data.elements) > 0
      end)
      
      if semantic_entries == [] do
        IO.puts("No semantic information found in any graph")
      else
        IO.puts("=== Semantic Information Across All Graphs ===")
        IO.puts("Found #{length(semantic_entries)} graphs with semantic data\n")
        
        Enum.each(semantic_entries, fn {graph_key, data} ->
          IO.puts("Graph: #{graph_key}")
          IO.puts("Elements: #{map_size(data.elements)}")
          
          if map_size(data.by_type) > 0 do
            IO.puts("By type:")
            Enum.each(data.by_type, fn {type, ids} ->
              IO.puts("  #{type}: #{length(ids)} element(s)")
              
              # Show details for each element
              Enum.each(ids, fn id ->
                elem = Map.get(data.elements, id)
                case type do
                  :text_buffer ->
                    IO.puts("    - Buffer #{elem.semantic.buffer_id}")
                    content_preview = String.slice(elem.content || "", 0, 50)
                    if content_preview != "", do: IO.puts("      Content: #{inspect(content_preview)}")
                    
                  :button ->
                    IO.puts("    - Button: #{elem.semantic.label}")
                    
                  _ ->
                    IO.puts("    - #{inspect(elem.semantic)}")
                end
              end)
            end)
          end
          IO.puts("")
        end)
      end
      :ok
    end
  end
  
  @doc """
  Show all text buffers across all graphs.
  """
  def buffers_all(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Find all text buffers
      all_buffers = Enum.flat_map(entries, fn {graph_key, data} ->
        buffer_ids = Map.get(data.by_type, :text_buffer, [])
        
        Enum.map(buffer_ids, fn id ->
          elem = Map.get(data.elements, id)
          %{
            graph_key: graph_key,
            buffer_id: elem.semantic.buffer_id,
            content: elem.content || "",
            semantic: elem.semantic
          }
        end)
      end)
      
      if all_buffers == [] do
        IO.puts("No text buffers found")
      else
        IO.puts("Text Buffers:")
        Enum.each(all_buffers, fn buffer ->
          content_preview = String.slice(buffer.content, 0, 60)
          content_preview = if String.length(buffer.content) > 60, do: content_preview <> "...", else: content_preview
          
          IO.puts("\n[Buffer: #{buffer.buffer_id}]")
          IO.puts("Graph: #{buffer.graph_key}")
          IO.puts("Content: #{inspect(content_preview)}")
        end)
      end
      :ok
    end
  end
  
  @doc """
  Get content of a specific buffer by UUID.
  """
  def buffer_by_uuid(buffer_uuid, viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Search for the buffer
      result = Enum.find_value(entries, fn {_graph_key, data} ->
        buffer_ids = Map.get(data.by_type, :text_buffer, [])
        
        Enum.find_value(buffer_ids, fn id ->
          elem = Map.get(data.elements, id)
          if elem.semantic.buffer_id == buffer_uuid do
            elem.content || ""
          end
        end)
      end)
      
      case result do
        nil -> 
          IO.puts("Buffer #{buffer_uuid} not found")
          :error
        content ->
          IO.puts("Buffer #{buffer_uuid}:")
          IO.puts(content)
          :ok
      end
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