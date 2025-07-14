defmodule Scenic.DevTools do
  @moduledoc """
  Comprehensive developer tools for inspecting Scenic applications during development.
  
  This module combines basic semantic inspection, UUID-aware enhanced tools,
  and high-level "browser dev tools" style inspection into a single namespace.
  
  ## Usage in IEx
  
      iex> import Scenic.DevTools
      
      # High-level inspection (recommended)
      iex> inspect_app()           # Browser dev tools style view
      iex> show_semantic()         # Simple semantic content overview
      
      # Detailed queries
      iex> semantic()              # Show semantic info for default viewport
      iex> buffers()               # Show all text buffers
      iex> buttons()               # Show all buttons
      
      # Enhanced tools for UUID graphs
      iex> semantic_all()          # All semantic data across graphs
      iex> buffers_all()           # All buffers across graphs
  """
  
  alias Scenic.ViewPort
  
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
         {:ok, buffers} <- Scenic.Semantic.Query.find_by_type(viewport, :text_buffer, graph_key) do
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
         {:ok, content} <- Scenic.Semantic.Query.get_buffer_text(viewport, buffer_id, graph_key) do
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
         {:ok, buttons} <- Scenic.Semantic.Query.get_buttons(viewport, graph_key) do
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
         {:ok, elements} <- Scenic.Semantic.Query.find_by_type(viewport, type, graph_key) do
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
  
  # =============================================================================
  # Enhanced Tools (UUID-aware)
  # =============================================================================
  
  @doc """
  Display all semantic information across all graphs.
  
  This function works with UUID graph keys and shows semantic data
  from all graphs in the viewport.
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
  
  # =============================================================================
  # High-Level Inspector (Browser Dev Tools Style)
  # =============================================================================
  
  @doc """
  Inspect your entire Scenic application like browser dev tools.
  
  Shows a hierarchical view starting from the ViewPort with all scenes,
  graphs, and semantic annotations. Perfect for understanding your app structure.
  
  ## Examples
  
      iex> inspect_app()
      === Scenic Application Inspector ===
      ViewPort: :main_viewport (1440x855)
      
      📊 Total Graphs: 8
      🏷️  Graphs with Semantic Data: 2
      
      📋 All Graphs:
      ├── 🏷️  "ABC123..." (5 semantic elements)
      │   ├── 📝 text_buffer: buffer_id "uuid1" 
      │   ├── 🔘 button: "Save"
      │   └── 📂 menu: "File"
      ├── ⚪ "DEF456..." (no semantic data)
  """
  def inspect_app(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      IO.puts("=== Scenic Application Inspector ===")
      IO.puts("ViewPort: #{inspect(viewport_name)} (#{format_size(viewport.size)})")
      IO.puts("")
      
      # Get all semantic data
      all_entries = :ets.tab2list(viewport.semantic_table)
      
      graphs_with_semantic = Enum.filter(all_entries, fn {_key, data} ->
        map_size(data.elements) > 0
      end)
      
      total_graphs = length(all_entries)
      semantic_graphs = length(graphs_with_semantic)
      
      IO.puts("📊 Total Graphs: #{total_graphs}")
      IO.puts("🏷️  Graphs with Semantic Data: #{semantic_graphs}")
      IO.puts("")
      
      if semantic_graphs == 0 do
        IO.puts("ℹ️  No semantic annotations found. Add semantic metadata to your components:")
        IO.puts("   |> text(\"Hello\", semantic: Semantic.text_buffer(buffer_id: 1))")
        IO.puts("   |> rect({100, 40}, semantic: Semantic.button(\"Save\"))")
      else
        IO.puts("📋 All Graphs:")
        render_graph_tree(all_entries)
      end
      
      IO.puts("")
      IO.puts("💡 Use inspect_graph(\"graph_id\") to see details of a specific graph")
      
      :ok
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Inspect a specific graph in detail.
  
  Shows the full semantic structure of a single graph, like zooming in
  on one component in the browser dev tools.
  
  ## Examples
  
      iex> inspect_graph("ABC123...")
      === Graph Details: ABC123... ===
      
      🏷️  Semantic Elements: 5
      📅 Last Updated: 2024-01-15 14:30:22
      
      📝 text_buffer (1):
        └── Element #7: %{buffer_id: "uuid1", editable: true, role: :textbox}
            Content: "Hello, World!"
  """
  def inspect_graph(graph_key, viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      case :ets.lookup(viewport.semantic_table, graph_key) do
        [{^graph_key, data}] ->
          IO.puts("=== Graph Details: #{String.slice(graph_key, 0, 8)}... ===")
          IO.puts("")
          
          element_count = map_size(data.elements)
          timestamp = format_timestamp(data.timestamp)
          
          IO.puts("🏷️  Semantic Elements: #{element_count}")
          IO.puts("📅 Last Updated: #{timestamp}")
          IO.puts("")
          
          if element_count == 0 do
            IO.puts("⚪ No semantic elements in this graph")
          else
            render_semantic_details(data)
          end
          
          :ok
          
        [] ->
          IO.puts("❌ Graph not found: #{graph_key}")
          
          # Show available graphs
          all_entries = :ets.tab2list(viewport.semantic_table)
          IO.puts("\n📋 Available graphs:")
          Enum.each(all_entries, fn {key, _data} ->
            short_key = String.slice(key, 0, 8) <> "..."
            IO.puts("   #{short_key}")
          end)
          
          :error
      end
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Show just the semantic content - like a simplified view.
  
  Perfect for beginners who just want to see "what semantic stuff is in my app?"
  
  ## Examples
  
      iex> show_semantic()
      === Semantic Content in Your App ===
      
      📝 Text Buffers (2):
        • Buffer "uuid1": "Hello, World!"  
        • Buffer "uuid2": "def hello do..."
      
      🔘 Buttons (3):
        • "Save" 
        • "Cancel"
        • "Submit"
  """
  def show_semantic(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      IO.puts("=== Semantic Content in Your App ===")
      IO.puts("")
      
      # Collect all semantic elements across all graphs
      all_entries = :ets.tab2list(viewport.semantic_table)
      
      all_elements = Enum.flat_map(all_entries, fn {_key, data} ->
        Map.values(data.elements)
      end)
      
      if all_elements == [] do
        IO.puts("🚫 No semantic content found")
        IO.puts("")
        IO.puts("💡 To add semantic annotations to your components:")
        IO.puts("   |> text(\"Hello\", semantic: Semantic.text_buffer(buffer_id: 1))")
        IO.puts("   |> rect({100, 40}, semantic: Semantic.button(\"Save\"))")
      else
        # Group by semantic type
        by_type = Enum.group_by(all_elements, fn elem ->
          elem.semantic.type
        end)
        
        # Show each type
        Enum.each(by_type, fn {type, elements} ->
          count = length(elements)
          icon = get_type_icon(type)
          type_name = String.capitalize(to_string(type)) <> "s"
          
          IO.puts("#{icon} #{type_name} (#{count}):")
          
          Enum.each(elements, fn elem ->
            description = format_element_description(elem)
            IO.puts("  • #{description}")
          end)
          
          IO.puts("")
        end)
      end
      
      :ok
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  # =============================================================================
  # Private Helpers
  # =============================================================================
  
  defp render_graph_tree(all_entries) do
    {graphs_with_semantic, graphs_without} = Enum.split_with(all_entries, fn {_key, data} ->
      map_size(data.elements) > 0
    end)
    
    # Show graphs with semantic data first
    Enum.with_index(graphs_with_semantic, fn {key, data}, index ->
      is_last_semantic = index == length(graphs_with_semantic) - 1
      has_more_graphs = length(graphs_without) > 0
      
      connector = if is_last_semantic and not has_more_graphs, do: "└──", else: "├──"
      
      short_key = String.slice(key, 0, 8) <> "..."
      element_count = map_size(data.elements)
      
      IO.puts("#{connector} 🏷️  \"#{short_key}\" (#{element_count} semantic elements)")
      
      # Show a preview of elements
      data.elements
      |> Map.values()
      |> Enum.take(3)
      |> Enum.with_index()
      |> Enum.each(fn {elem, elem_index} ->
        is_last_elem = elem_index == min(2, element_count - 1)
        elem_connector = if is_last_semantic and not has_more_graphs and is_last_elem, do: "    └──", else: "│   ├──"
        
        icon = get_type_icon(elem.semantic.type)
        description = format_element_brief(elem)
        IO.puts("#{elem_connector} #{icon} #{description}")
      end)
      
      if element_count > 3 do
        more_connector = if is_last_semantic and not has_more_graphs, do: "    └──", else: "│   └──"
        IO.puts("#{more_connector} ... and #{element_count - 3} more")
      end
    end)
    
    # Show graphs without semantic data
    Enum.with_index(graphs_without, fn {key, _data}, index ->
      is_last = index == length(graphs_without) - 1
      connector = if is_last, do: "└──", else: "├──"
      
      short_key = String.slice(key, 0, 8) <> "..."
      IO.puts("#{connector} ⚪ \"#{short_key}\" (no semantic data)")
    end)
  end
  
  defp render_semantic_details(data) do
    Enum.each(data.by_type, fn {type, element_ids} ->
      icon = get_type_icon(type)
      type_name = String.capitalize(to_string(type))
      count = length(element_ids)
      
      IO.puts("#{icon} #{type_name} (#{count}):")
      
      Enum.each(element_ids, fn id ->
        elem = Map.get(data.elements, id)
        description = format_element_description(elem)
        IO.puts("  └── Element ##{id}: #{description}")
        
        # Show content if it's a text element
        if elem.content && String.trim(elem.content) != "" do
          content_preview = String.slice(elem.content, 0, 50)
          content_preview = if String.length(elem.content) > 50, do: content_preview <> "...", else: content_preview
          IO.puts("      Content: #{inspect(content_preview)}")
        end
      end)
      
      IO.puts("")
    end)
  end
  
  defp format_element_brief(elem) do
    case elem.semantic.type do
      :text_buffer -> "text_buffer: buffer_id \"#{String.slice(elem.semantic.buffer_id, 0, 8)}...\""
      :button -> "button: \"#{elem.semantic.label}\""
      :menu -> "menu: \"#{elem.semantic.name}\""
      :text_input -> "text_input: \"#{elem.semantic.name}\""
      other -> "#{other}: #{inspect(elem.semantic)}"
    end
  end
  
  defp format_element_description(elem) do
    case elem.semantic.type do
      :text_buffer -> 
        id = String.slice(elem.semantic.buffer_id, 0, 8) <> "..."
        preview = if elem.content && String.trim(elem.content) != "" do
          " - \"#{String.slice(elem.content, 0, 20)}...\""
        else
          " (empty)"
        end
        "Buffer #{id}#{preview}"
        
      :button -> "\"#{elem.semantic.label}\""
      :menu -> "\"#{elem.semantic.name}\" menu"
      :text_input -> "\"#{elem.semantic.name}\" input"
      _other -> "#{inspect(elem.semantic)}"
    end
  end
  
  defp get_type_icon(type) do
    case type do
      :text_buffer -> "📝"
      :button -> "🔘"
      :menu -> "📂"
      :text_input -> "📝"
      _ -> "🏷️"
    end
  end
  
  defp format_size({width, height}), do: "#{width}x#{height}"
  defp format_size(_), do: "unknown"
  
  defp format_timestamp(timestamp) when is_integer(timestamp) do
    # Convert from milliseconds since Unix epoch
    datetime = DateTime.from_unix!(timestamp, :millisecond)
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end
  defp format_timestamp(_), do: "unknown"
  
  defp get_viewport(viewport) when is_struct(viewport, ViewPort), do: {:ok, viewport}
  defp get_viewport(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, "ViewPort #{inspect(name)} not found"}
      pid -> ViewPort.info(pid)
    end
  end
  defp get_viewport(pid) when is_pid(pid), do: ViewPort.info(pid)
end