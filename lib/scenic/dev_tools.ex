defmodule Scenic.DevTools do
  @moduledoc """
  Generic developer tools for inspecting Scenic applications during development.
  
  This module provides tools for understanding the structure and state of any
  Scenic application, focusing on the graph hierarchy and semantic annotations.
  
  ## Usage in IEx
  
      iex> import Scenic.DevTools
      
      # High-level inspection (recommended)
      iex> inspect_app()           # Hierarchical view of scenes and graphs
      iex> show_semantic()         # All semantic content in the app
      
      # Scene hierarchy
      iex> scene_tree()            # Show scene parent-child relationships
      iex> inspect_scene("_main_") # Detailed view of a specific scene
      
      # Graph inspection  
      iex> inspect_graph("uuid")   # Detailed view of a specific graph
      iex> list_graphs()           # List all graphs with their scenes
      
      # Semantic queries (generic)
      iex> semantic_summary()      # Summary of all semantic annotations
      iex> find_semantic(:button)  # Find all elements of a semantic type
  """
  
  alias Scenic.ViewPort
  
  @doc """
  Show the scene hierarchy as a tree structure.
  
  Displays the parent-child relationships between scenes, starting from
  the root scene and showing all descendant scenes.
  
  ## Examples
  
      iex> scene_tree()
      === Scene Hierarchy ===
      📊 Root Scene: "_main_" (Flamelex.GUI.RootScene)
      ├── 📄 "layer_1" (Flamelex.GUI.Layers.Layer1)
      ├── 📄 "layer_2" (Flamelex.GUI.Layers.Layer2) 
      │   └── 📄 "buffer_pane_abc123" (Quillex.BufferPane)
      └── 📄 "layer_4" (Flamelex.GUI.Layers.Layer4)
  """
  def scene_tree(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      IO.puts("=== Scene Hierarchy ===")
      
      # Build the scene tree
      tree = build_scene_tree(viewport)
      
      if tree do
        render_scene_node(tree, "")
      else
        IO.puts("No scenes found in viewport")
      end
      
      :ok
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  List all graphs showing which scene owns each graph.
  
  ## Examples
  
      iex> list_graphs()
      === Graphs in ViewPort ===
      Total graphs: 5
      
      Graph "_root_" (root scene graph)
        Scene: "_main_" (Flamelex.GUI.RootScene)
        Has semantic data: Yes (3 elements)
      
      Graph "abc123..."  
        Scene: "buffer_pane_1" (Quillex.BufferPane)
        Has semantic data: Yes (1 element)
  """
  def list_graphs(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      IO.puts("=== Graphs in ViewPort ===")
      
      # Get all scripts from the script table
      scripts = :ets.tab2list(viewport.script_table)
      semantic_entries = :ets.tab2list(viewport.semantic_table)
      
      IO.puts("Total graphs: #{length(scripts)}")
      IO.puts("")
      
      # Group scripts by their scene
      Enum.each(scripts, fn {graph_id, _script, owner_pid} ->
        # Find scene info for this owner
        scene_info = find_scene_by_pid(viewport, owner_pid)
        
        # Check if has semantic data
        semantic_info = Enum.find(semantic_entries, fn {id, _data} -> id == graph_id end)
        has_semantic = case semantic_info do
          {_, data} -> map_size(data.elements) > 0
          nil -> false
        end
        
        graph_label = if graph_id == "_root_", do: "(root scene graph)", else: ""
        IO.puts("Graph \"#{short_id(graph_id)}\" #{graph_label}")
        
        case scene_info do
          {scene_id, module} ->
            IO.puts("  Scene: \"#{scene_id}\" (#{inspect(module)})")
          nil ->
            IO.puts("  Scene: Unknown (pid: #{inspect(owner_pid)})")
        end
        
        if has_semantic do
          {_, data} = semantic_info
          IO.puts("  Has semantic data: Yes (#{map_size(data.elements)} elements)")
        else
          IO.puts("  Has semantic data: No")
        end
        
        IO.puts("")
      end)
      
      :ok
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Show a summary of all semantic annotations in the application.
  
  Groups semantic elements by type across all graphs.
  
  ## Examples
  
      iex> semantic_summary()
      === Semantic Summary ===
      Total semantic elements: 15 across 3 graphs
      
      By type:
        button: 5 elements
        text_input: 3 elements  
        menu: 2 elements
        custom_widget: 5 elements
  """
  def semantic_summary(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Filter to only entries with semantic data
      semantic_entries = Enum.filter(entries, fn {_key, data} ->
        map_size(data.elements) > 0
      end)
      
      # Collect all semantic elements across all graphs
      all_elements = Enum.flat_map(semantic_entries, fn {_graph_key, data} ->
        Map.values(data.elements)
      end)
      
      total_elements = length(all_elements)
      graph_count = length(semantic_entries)
      
      IO.puts("=== Semantic Summary ===")
      IO.puts("Total semantic elements: #{total_elements} across #{graph_count} graphs")
      IO.puts("")
      
      if total_elements == 0 do
        IO.puts("No semantic annotations found.")
        IO.puts("Add semantic metadata to your components:")
        IO.puts("  |> rect({100, 40}, semantic: %{type: :button, label: \"Save\"})")
      else
        # Group by type
        by_type = Enum.group_by(all_elements, fn elem -> elem.semantic.type end)
        
        IO.puts("By type:")
        by_type
        |> Enum.sort_by(fn {_type, elems} -> -length(elems) end)
        |> Enum.each(fn {type, elements} ->
          IO.puts("  #{type}: #{length(elements)} elements")
        end)
      end
      
      :ok
    end
  end
  
  @doc """
  Find all semantic elements of a given type across all graphs.
  
  ## Examples
  
      iex> find_semantic(:button)
      === Elements of type :button ===
      Found 3 elements:
      
      Graph "abc123...":
        - %{type: :button, label: "Save"}
        - %{type: :button, label: "Cancel"}
      
      Graph "def456...":
        - %{type: :button, label: "Submit"}
  """
  def find_semantic(type, viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      # Find all elements of this type
      results = Enum.flat_map(entries, fn {graph_key, data} ->
        element_ids = Map.get(data.by_type, type, [])
        
        elements = Enum.map(element_ids, fn id ->
          elem = Map.get(data.elements, id)
          {graph_key, elem}
        end)
        
        if elements == [], do: [], else: [{graph_key, elements}]
      end)
      
      IO.puts("=== Elements of type #{inspect(type)} ===")
      
      if results == [] do
        IO.puts("No elements found")
      else
        total = Enum.reduce(results, 0, fn {_, elems}, acc -> acc + length(elems) end)
        IO.puts("Found #{total} elements:")
        IO.puts("")
        
        Enum.each(results, fn {graph_key, elements} ->
          IO.puts("Graph \"#{short_id(graph_key)}\":")
          Enum.each(elements, fn {_graph_key, elem} ->
            IO.puts("  - #{inspect(elem.semantic)}")
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
  
  @doc """
  Inspect a specific scene showing its graph and semantic data.
  
  ## Examples
  
      iex> inspect_scene("_main_")
      === Scene: "_main_" ===
      Module: Flamelex.GUI.RootScene
      Graph ID: "_root_"
      Child scenes: 4
      
      Semantic elements in graph:
        - button: "File" menu
        - button: "Edit" menu
  """
  def inspect_scene(scene_id, viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      case Map.get(viewport.scenes_by_id, scene_id) do
        nil ->
          IO.puts("Scene \"#{scene_id}\" not found")
          available = Map.keys(viewport.scenes_by_id)
          IO.puts("\nAvailable scenes: #{inspect(available)}")
          :error
          
        {pid, parent_pid} ->
          # Get scene info from pid map
          {^scene_id, _parent_id, module} = Map.get(viewport.scenes_by_pid, pid)
          
          IO.puts("=== Scene: \"#{scene_id}\" ===")
          IO.puts("Module: #{inspect(module)}")
          IO.puts("PID: #{inspect(pid)}")
          if parent_pid, do: IO.puts("Parent PID: #{inspect(parent_pid)}")
          
          # Find the graph for this scene
          scripts = :ets.tab2list(viewport.script_table)
          scene_graphs = Enum.filter(scripts, fn {_id, _script, owner} -> owner == pid end)
          
          if scene_graphs != [] do
            IO.puts("\nGraphs owned by this scene:")
            Enum.each(scene_graphs, fn {graph_id, _script, _owner} ->
              IO.puts("  Graph ID: \"#{short_id(graph_id)}\"")
              
              # Check semantic data
              case :ets.lookup(viewport.semantic_table, graph_id) do
                [{^graph_id, data}] when map_size(data.elements) > 0 ->
                  IO.puts("    Semantic elements:")
                  Enum.each(data.by_type, fn {type, ids} ->
                    IO.puts("      - #{type}: #{length(ids)} element(s)")
                  end)
                _ ->
                  IO.puts("    No semantic data")
              end
            end)
          end
          
          # Find child scenes
          children = Enum.filter(viewport.scenes_by_pid, fn {child_pid, _} ->
            case Map.get(viewport.scenes_by_id, Map.get(viewport.scenes_by_pid, child_pid) |> elem(0)) do
              {^child_pid, ^pid} -> true
              _ -> false
            end
          end)
          
          if children != [] do
            IO.puts("\nChild scenes: #{length(children)}")
            Enum.each(children, fn {_child_pid, {child_id, _, child_module}} ->
              IO.puts("  - \"#{child_id}\" (#{inspect(child_module)})")
            end)
          end
          
          :ok
      end
    else
      error -> 
        IO.puts("Error: #{inspect(error)}")
        :error
    end
  end
  
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
  
  # Private helper to build scene tree
  defp build_scene_tree(viewport) do
    # Find root scene
    root_entry = Enum.find(viewport.scenes_by_id, fn {id, _} -> 
      id == "_main_" 
    end)
    
    case root_entry do
      {root_id, {root_pid, _parent}} ->
        {^root_id, _parent_id, module} = Map.get(viewport.scenes_by_pid, root_pid)
        build_scene_node(root_id, root_pid, module, viewport)
      nil ->
        nil
    end
  end
  
  defp build_scene_node(id, pid, module, viewport) do
    # Find children of this scene
    children = Enum.filter(viewport.scenes_by_id, fn {_child_id, {_child_pid, parent_pid}} ->
      parent_pid == pid
    end)
    
    # Build child nodes
    child_nodes = Enum.map(children, fn {child_id, {child_pid, _}} ->
      {^child_id, _, child_module} = Map.get(viewport.scenes_by_pid, child_pid)
      build_scene_node(child_id, child_pid, child_module, viewport)
    end)
    
    %{
      id: id,
      pid: pid,
      module: module,
      children: child_nodes
    }
  end
  
  defp render_scene_node(node, prefix) do
    # Determine if this is the last child at this level
    is_root = prefix == ""
    
    # Render this node
    icon = if node.id == "_main_", do: "📊", else: "📄"
    label = if node.id == "_main_", do: "Root Scene: ", else: ""
    
    if is_root do
      IO.puts("#{icon} #{label}\"#{node.id}\" (#{inspect(node.module)})")
    else
      IO.puts("#{prefix}#{icon} \"#{node.id}\" (#{inspect(node.module)})")
    end
    
    # Render children
    Enum.with_index(node.children, fn child, index ->
      is_last = index == length(node.children) - 1
      
      {child_prefix, next_prefix} = if is_root do
        child_prefix = if is_last, do: "└── ", else: "├── "
        next_prefix = if is_last, do: "    ", else: "│   "
        {child_prefix, next_prefix}
      else
        child_prefix = if is_last, do: "#{prefix}└── ", else: "#{prefix}├── "
        next_prefix = if is_last, do: "#{prefix}    ", else: "#{prefix}│   "
        {child_prefix, next_prefix}
      end
      
      render_scene_node(child, child_prefix)
      
      # Continue with grandchildren using the appropriate prefix
      Enum.each(child.children, fn grandchild ->
        render_scene_node(grandchild, next_prefix)
      end)
    end)
  end
  
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
  
  # Helper to find scene info by pid
  defp find_scene_by_pid(viewport, pid) do
    case Map.get(viewport.scenes_by_pid, pid) do
      {id, _parent_id, module} -> {id, module}
      nil -> nil
    end
  end
  
  # Helper to shorten long IDs
  defp short_id(id) when byte_size(id) > 12 do
    String.slice(id, 0, 8) <> "..."
  end
  defp short_id(id), do: id
  
  defp get_viewport(viewport) when is_struct(viewport, ViewPort), do: {:ok, viewport}
  defp get_viewport(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, "ViewPort #{inspect(name)} not found"}
      pid -> ViewPort.info(pid)
    end
  end
  defp get_viewport(pid) when is_pid(pid), do: ViewPort.info(pid)
end