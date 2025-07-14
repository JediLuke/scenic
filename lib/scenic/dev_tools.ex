defmodule Scenic.DevTools do
  @moduledoc """
  Developer tools for inspecting Scenic applications during development.
  
  This module provides a unified interface for understanding the structure,
  state, and semantic content of Scenic applications. It's designed for
  development, testing, automation, and accessibility.
  
  ## Quick Start
  
      iex> import Scenic.DevTools
      iex> inspect_viewport()      # The main inspection function
  
  ## Other Tools
  
      iex> semantic()              # Just semantic content  
      iex> buffers()               # Text buffer shortcuts
      iex> find(:button)           # Find elements by type
  """
  
  alias Scenic.ViewPort
  
  @doc """
  The primary inspection function for Scenic applications.
  
  Provides a unified view of:
  - ViewPort configuration
  - Scene hierarchy with relationships
  - Graphs with their semantic content
  - Interactive elements summary
  
  This replaces both scene_tree() and inspect_app() with a cleaner,
  more informative display.
  
  ## Options
  
    * `:viewport` - ViewPort name or pid (default: `:main_viewport`)
    * `:graph` - Specific graph to inspect (default: all graphs)
    * `:show` - What to display: `:all`, `:scenes`, `:semantic`, `:graphs`
    * `:verbose` - Show additional details (default: false)
  
  ## Examples
  
      # Default view - everything
      iex> inspect_viewport()
      
      # Just semantic content
      iex> inspect_viewport(show: :semantic)
      
      # Specific graph with details
      iex> inspect_viewport(graph: "abc123", verbose: true)
      
      # Different viewport
      iex> inspect_viewport(viewport: :secondary)
  """
  def inspect_viewport(opts \\ []) do
    viewport_name = Keyword.get(opts, :viewport, :main_viewport)
    show = Keyword.get(opts, :show, :all)
    graph_filter = Keyword.get(opts, :graph)
    verbose = Keyword.get(opts, :verbose, false)
    
    with {:ok, viewport} <- get_viewport(viewport_name) do
      IO.puts("\n╔═══ Scenic ViewPort Inspector ═══╗")
      IO.puts("║ ViewPort: #{inspect(viewport_name)}")
      IO.puts("║ Size: #{format_size(viewport.size)}")
      IO.puts("╚═════════════════════════════════╝\n")
      
      case show do
        :all ->
          show_hierarchy_if_available(viewport)
          show_graphs_with_semantic(viewport, graph_filter, verbose)
          show_semantic_summary(viewport)
          
        :hierarchy ->
          show_hierarchy_if_available(viewport)
          
        :scenes ->
          show_hierarchy_if_available(viewport)
          
        :semantic ->
          show_graphs_with_semantic(viewport, graph_filter, verbose)
          show_semantic_summary(viewport)
          
        :graphs ->
          show_graphs_with_semantic(viewport, graph_filter, verbose)
      end
      
      show_quick_tips()
      :ok
    else
      error -> 
        IO.puts("❌ Error: #{inspect(error)}")
        :error
    end
  end
  
  @doc """
  Show all semantic content across the application.
  
  A simplified view focusing just on the semantic elements,
  organized by type with content previews.
  """
  def semantic(viewport_name \\ :main_viewport, graph_key \\ nil) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      if graph_key do
        # Show semantic for specific graph
        show_graph_semantic(viewport, graph_key)
      else
        # Show all semantic content
        show_all_semantic(viewport)
      end
      :ok
    end
  end
  
  
  @doc """
  Find elements by semantic type.
  
  ## Examples
  
      iex> find(:button)
      iex> find(:text_buffer)
      iex> find(:menu)
  """
  def find(type, viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      elements = for {graph_key, data} <- entries,
                     id <- Map.get(data.by_type, type, []),
                     elem = Map.get(data.elements, id),
                     do: {graph_key, elem}
      
      if elements == [] do
        IO.puts("No #{type} elements found")
        show_available_types(entries)
      else
        icon = get_type_icon(type)
        IO.puts("\n#{icon} Found #{length(elements)} #{type} element(s):")
        
        Enum.group_by(elements, fn {graph_key, _} -> graph_key end)
        |> Enum.each(fn {graph_key, elems} ->
          IO.puts("\nGraph \"#{short_id(graph_key)}\":")
          Enum.each(elems, fn {_, elem} ->
            desc = format_element_for_find(elem)
            IO.puts("  • #{desc}")
          end)
        end)
      end
      :ok
    end
  end
  
  @doc """
  List all semantic types in use.
  """
  def types(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.semantic_table)
      
      type_counts = entries
        |> Enum.flat_map(fn {_, data} -> 
          Enum.map(data.by_type, fn {type, ids} -> {type, length(ids)} end)
        end)
        |> Enum.reduce(%{}, fn {type, count}, acc ->
          Map.update(acc, type, count, &(&1 + count))
        end)
      
      if map_size(type_counts) == 0 do
        IO.puts("No semantic types found")
      else
        IO.puts("\n🏷️  Semantic Types in Use:")
        type_counts
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.each(fn {type, count} ->
          icon = get_type_icon(type)
          IO.puts("#{icon} #{type}: #{count} element(s)")
        end)
      end
      :ok
    end
  end
  
  @doc """
  Get raw semantic data for advanced queries.
  
  Returns the semantic data structure that you can
  query programmatically.
  """
  def raw_semantic(viewport_name \\ :main_viewport, graph_key \\ nil) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      if graph_key do
        case :ets.lookup(viewport.semantic_table, graph_key) do
          [{^graph_key, data}] -> data
          [] -> nil
        end
      else
        # Return all semantic data
        entries = :ets.tab2list(viewport.semantic_table)
        Map.new(entries)
      end
    end
  end

  @doc """
  Get enhanced scene script data with hierarchy and metadata.
  
  This provides access to the enhanced scene_script layer that includes
  all elements (not just semantic ones), hierarchy relationships,
  and automation-friendly metadata.
  
  ## Examples
  
      # Get all scene scripts
      iex> raw_scene_script()
      
      # Get specific graph's script data
      iex> raw_scene_script(:main_viewport, "graph_key")
  """
  def raw_scene_script(viewport_name \\ :main_viewport, graph_key \\ nil) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      if graph_key do
        case :ets.lookup(viewport.scene_script_table, graph_key) do
          [{^graph_key, data}] -> data
          [] -> nil
        end
      else
        # Return all scene script data
        entries = :ets.tab2list(viewport.scene_script_table)
        Map.new(entries)
      end
    end
  end

  @doc """
  Show the hierarchical structure of graphs.
  
  This displays the parent-child relationships between graphs,
  providing a tree view of how your application is structured.
  """
  def hierarchy(viewport_name \\ :main_viewport) do
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.scene_script_table)
      
      if entries == [] do
        IO.puts("📊 No graphs found")
      else
        IO.puts("\n🏗️  Graph Hierarchy:")
        IO.puts("──────────────────")
        
        # Find root graphs (no parent)
        roots = Enum.filter(entries, fn {_, data} -> 
          data.parent == nil 
        end)
        
        if roots == [] do
          IO.puts("  No root graphs found")
        else
          Enum.each(roots, fn {key, data} ->
            render_hierarchy_tree(key, data, entries, "", false)
          end)
        end
      end
      :ok
    end
  end

  @doc """
  Find elements across all graphs with advanced filtering.
  
  Supports finding by:
  - Semantic type (`:text_buffer`, `:button`)
  - Accessibility role (`:textbox`, `:button`)  
  - Primitive type (`Scenic.Primitive.Text`)
  - Graph location
  
  ## Examples
  
      # Find by semantic type
      iex> find_element(type: :text_buffer)
      
      # Find by role
      iex> find_element(role: :button)
      
      # Find by primitive type
      iex> find_element(primitive: Scenic.Primitive.Text)
      
      # Find within specific graph
      iex> find_element(type: :button, in_graph: "main_graph")
  """
  def find_element(opts, viewport_name \\ :main_viewport) do
    type = Keyword.get(opts, :type)
    role = Keyword.get(opts, :role)  
    primitive = Keyword.get(opts, :primitive)
    in_graph = Keyword.get(opts, :in_graph)
    
    with {:ok, viewport} <- get_viewport(viewport_name) do
      entries = :ets.tab2list(viewport.scene_script_table)
      
      # Filter by graph if specified
      entries = if in_graph do
        Enum.filter(entries, fn {key, _} -> 
          String.contains?(to_string(key), in_graph)
        end)
      else
        entries
      end
      
      # Find matching elements
      elements = find_matching_elements(entries, type: type, role: role, primitive: primitive)
      
      display_found_elements(elements, opts)
      :ok
    end
  end
  
  # ============================================================================
  # Private Display Functions
  # ============================================================================

  defp show_hierarchy_if_available(viewport) do
    # Check if scene_script_table is available and has data
    entries = :ets.tab2list(viewport.scene_script_table)
    
    if entries != [] do
      IO.puts("🏗️  Graph Hierarchy:")
      IO.puts("──────────────────")
      
      # Find root graphs (no parent)
      roots = Enum.filter(entries, fn {_, data} -> 
        data.parent == nil 
      end)
      
      if roots == [] do
        IO.puts("  No root graphs found")
      else
        Enum.each(roots, fn {key, data} ->
          render_hierarchy_tree(key, data, entries, "", false)
        end)
      end
      IO.puts("")
    else
      IO.puts("⚠️  Graph hierarchy data not available")
      IO.puts("   (Scene script enhancement not yet populated)")
      IO.puts("")
    end
  end
  
  
  defp show_graphs_with_semantic(viewport, graph_filter, verbose) do
    entries = :ets.tab2list(viewport.semantic_table)
    
    # Filter if specific graph requested
    entries = if graph_filter do
      Enum.filter(entries, fn {key, _} -> 
        String.contains?(key, graph_filter)
      end)
    else
      entries
    end
    
    if entries == [] do
      if graph_filter do
        IO.puts("📊 No graphs matching: #{graph_filter}")
      else
        IO.puts("📊 No graphs found")
      end
    else
      IO.puts("📊 Graphs & Semantic Content:")
      IO.puts("────────────────────────────")
      
      # Group by whether they have semantic content
      {with_semantic, without} = Enum.split_with(entries, fn {_, data} ->
        map_size(data.elements) > 0
      end)
      
      # Show graphs with semantic content first
      if with_semantic != [] do
        IO.puts("\n🏷️  With Semantic Data:")
        Enum.each(with_semantic, fn {key, data} ->
          render_graph_semantic(key, data, verbose, viewport)
        end)
      end
      
      # Then graphs without
      if without != [] and verbose do
        IO.puts("\n⚪ Without Semantic Data:")
        Enum.each(without, fn {key, _} ->
          IO.puts("  • Graph \"#{short_id(key)}\"")
        end)
      end
      
      IO.puts("")
    end
  end
  
  defp show_semantic_summary(viewport) do
    entries = :ets.tab2list(viewport.semantic_table)
    
    all_elements = for {_, data} <- entries,
                       {_, elem} <- data.elements,
                       do: elem
    
    if all_elements != [] do
      IO.puts("📈 Semantic Summary:")
      IO.puts("──────────────────")
      
      # Group by type and show counts
      all_elements
      |> Enum.group_by(& &1.semantic.type)
      |> Enum.sort_by(fn {_, elems} -> -length(elems) end)
      |> Enum.each(fn {type, elems} ->
        icon = get_type_icon(type)
        count = length(elems)
        
        # Show sample for common types
        sample = case type do
          :button ->
            labels = elems 
              |> Enum.map(& &1.semantic[:label])
              |> Enum.filter(& &1)
              |> Enum.take(3)
            if labels != [], do: " (#{Enum.join(labels, ", ")})", else: ""
            
          :text_buffer ->
            " (#{count} buffer#{if count > 1, do: "s", else: ""})"
            
          _ -> ""
        end
        
        IO.puts("  #{icon} #{type}: #{count}#{sample}")
      end)
      
      IO.puts("")
    end
  end
  
  defp show_quick_tips do
    IO.puts("💡 Quick Commands:")
    IO.puts("  • inspect_viewport(show: :semantic)  # Just semantic content")
    IO.puts("  • hierarchy()                        # Show graph structure")
    IO.puts("  • find(:button)                      # Find by semantic type")
    IO.puts("  • find_element(role: :textbox)       # Find by accessibility role")
    IO.puts("  • types()                            # List all semantic types")
    IO.puts("  • semantic()                         # All semantic content")
    IO.puts("  • raw_scene_script()                 # Enhanced data with hierarchy")
  end
  
  # ============================================================================
  # Private Semantic Display Functions
  # ============================================================================
  
  defp show_graph_semantic(viewport, graph_key) do
    case :ets.lookup(viewport.semantic_table, graph_key) do
      [{^graph_key, data}] ->
        IO.puts("\n📊 Semantic Data for Graph \"#{short_id(graph_key)}\":")
        if map_size(data.elements) == 0 do
          IO.puts("  No semantic elements")
        else
          render_semantic_elements(data)
        end
      [] ->
        IO.puts("Graph not found: #{graph_key}")
    end
  end
  
  defp show_all_semantic(viewport) do
    entries = :ets.tab2list(viewport.semantic_table)
    
    all_elements = for {_, data} <- entries,
                       {_, elem} <- data.elements,
                       do: elem
    
    if all_elements == [] do
      IO.puts("\n🚫 No semantic content found")
      IO.puts("\n💡 Add semantic annotations:")
      IO.puts("  |> text(\"Hello\", semantic: Semantic.text_buffer(buffer_id: 1))")
      IO.puts("  |> rect({100, 40}, semantic: Semantic.button(\"Save\"))")
    else
      IO.puts("\n🏷️  All Semantic Content:")
      
      # Group by type
      all_elements
      |> Enum.group_by(& &1.semantic.type)
      |> Enum.sort_by(fn {type, _} -> type end)
      |> Enum.each(fn {type, elems} ->
        icon = get_type_icon(type)
        IO.puts("\n#{icon} #{String.capitalize(to_string(type))} (#{length(elems)}):")
        
        Enum.each(elems, fn elem ->
          desc = format_semantic_element(elem)
          IO.puts("  • #{desc}")
        end)
      end)
    end
  end
  
  # ============================================================================
  # Rendering Helpers
  # ============================================================================
  
  
  defp render_graph_semantic(key, data, verbose, _viewport) do
    element_count = map_size(data.elements)
    
    IO.puts("\n  📋 \"#{short_id(key)}\"")
    IO.puts("     Elements: #{element_count}")
    
    if element_count > 0 do
      # Group by type for cleaner display
      by_type = Enum.group_by(Map.values(data.elements), & &1.semantic.type)
      
      Enum.each(by_type, fn {type, elems} ->
        icon = get_type_icon(type)
        
        if verbose do
          IO.puts("     #{icon} #{type} (#{length(elems)}):")
          Enum.each(elems, fn elem ->
            desc = format_element_line(elem)
            IO.puts("        • #{desc}")
          end)
        else
          # Compact view - show count only
          count = length(elems)
          IO.puts("     #{icon} #{type}: #{count} element#{if count > 1, do: "s", else: ""}")
        end
      end)
    end
  end
  
  defp render_semantic_elements(data) do
    data.by_type
    |> Enum.sort_by(fn {type, _} -> type end)
    |> Enum.each(fn {type, ids} ->
      icon = get_type_icon(type)
      IO.puts("\n  #{icon} #{type} (#{length(ids)}):")
      
      Enum.each(ids, fn id ->
        elem = Map.get(data.elements, id)
        desc = format_semantic_element(elem)
        IO.puts("    • #{desc}")
      end)
    end)
  end
  
  # ============================================================================
  # Formatting Helpers
  # ============================================================================
  
  defp format_element_line(elem) do
    case elem.semantic.type do
      :text_buffer ->
        lines = if elem.content, do: length(String.split(elem.content, "\n")), else: 0
        "Buffer #{short_id(elem.semantic.buffer_id)} (#{lines} lines)"
        
      :button ->
        "\"#{elem.semantic.label}\""
        
      :menu ->
        "\"#{elem.semantic.name}\""
        
      _ ->
        inspect(elem.semantic, limit: 1, pretty: false)
    end
  end
  
  
  defp format_semantic_element(elem) do
    semantic = elem.semantic
    
    case semantic.type do
      :text_buffer ->
        id = short_id(semantic.buffer_id)
        content_info = if elem.content && elem.content != "" do
          lines = length(String.split(elem.content, "\n"))
          chars = String.length(elem.content)
          " - #{lines} lines, #{chars} chars"
        else
          " - empty"
        end
        "#{id}#{content_info}"
        
      :button ->
        "\"#{semantic.label}\""
        
      :menu ->
        "\"#{semantic.name}\" (#{semantic[:orientation] || :vertical})"
        
      :text_input ->
        name = semantic.name
        placeholder = if semantic[:placeholder], do: " (#{semantic.placeholder})", else: ""
        "\"#{name}\"#{placeholder}"
        
      _ ->
        # For custom types, show key attributes
        attrs = semantic
          |> Map.drop([:type])
          |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v, limit: 1)}" end)
          |> Enum.join(", ")
        
        if attrs == "", do: "#{semantic.type}", else: "#{attrs}"
    end
  end
  
  defp format_element_for_find(elem) do
    case elem.semantic.type do
      :text_buffer ->
        id = short_id(elem.semantic.buffer_id)
        preview = if elem.content && elem.content != "" do
          first_line = elem.content |> String.split("\n") |> List.first() |> String.slice(0, 40)
          " - \"#{first_line}...\""
        else
          " - (empty)"
        end
        "Buffer #{id}#{preview}"
        
      :button ->
        "\"#{elem.semantic.label}\""
        
      _ ->
        format_semantic_element(elem)
    end
  end
  
  # ============================================================================
  # Scene Script Helpers
  # ============================================================================

  defp render_hierarchy_tree(key, data, all_entries, prefix, verbose) do
    element_count = map_size(data.elements)
    
    # Show type counts for the graph
    type_info = if element_count > 0 do
      semantic_types = Map.keys(data.by_type) |> Enum.join(", ")
      " (#{element_count} elements: #{semantic_types})"
    else
      " (empty)"
    end
    
    IO.puts("#{prefix}📊 #{short_id(key)}#{type_info}")
    
    # Show children
    children = Enum.filter(all_entries, fn {child_key, child_data} ->
      child_data.parent == key
    end)
    
    Enum.with_index(children)
    |> Enum.each(fn {{child_key, child_data}, idx} ->
      is_last = idx == length(children) - 1
      child_prefix = prefix <> if is_last, do: "└── ", else: "├── "
      next_prefix = prefix <> if is_last, do: "    ", else: "│   "
      
      render_hierarchy_tree(child_key, child_data, all_entries, child_prefix, verbose)
    end)
  end

  defp find_matching_elements(entries, opts) do
    type = Keyword.get(opts, :type)
    role = Keyword.get(opts, :role)
    primitive = Keyword.get(opts, :primitive)
    
    entries
    |> Enum.flat_map(fn {graph_key, data} ->
      matching_ids = []
      
      # Find by semantic type
      matching_ids = if type do
        Map.get(data.by_type, type, []) ++ matching_ids
      else
        matching_ids
      end
      
      # Find by role
      matching_ids = if role do
        Map.get(data.by_role, role, []) ++ matching_ids
      else
        matching_ids
      end
      
      # Find by primitive type
      matching_ids = if primitive do
        Map.get(data.by_primitive, primitive, []) ++ matching_ids
      else
        matching_ids
      end
      
      # If no filters specified, return all elements
      matching_ids = if type == nil and role == nil and primitive == nil do
        Map.keys(data.elements)
      else
        matching_ids |> Enum.uniq()
      end
      
      # Convert IDs to full element data
      Enum.map(matching_ids, fn id ->
        elem = Map.get(data.elements, id)
        {graph_key, id, elem}
      end)
    end)
  end

  defp display_found_elements(elements, opts) do
    if elements == [] do
      IO.puts("No matching elements found")
      suggest_available_options(opts)
    else
      filter_desc = describe_filters(opts)
      IO.puts("\n🔍 Found #{length(elements)} element(s)#{filter_desc}:")
      
      # Group by graph for cleaner display
      elements
      |> Enum.group_by(fn {graph_key, _, _} -> graph_key end)
      |> Enum.each(fn {graph_key, graph_elements} ->
        IO.puts("\nGraph \"#{short_id(graph_key)}\":")
        
        Enum.each(graph_elements, fn {_, id, elem} ->
          desc = format_element_detailed(elem)
          IO.puts("  • [#{id}] #{desc}")
        end)
      end)
    end
  end

  defp describe_filters(opts) do
    filters = []
    
    filters = if type = Keyword.get(opts, :type) do
      ["type: #{type}" | filters]
    else
      filters
    end
    
    filters = if role = Keyword.get(opts, :role) do
      ["role: #{role}" | filters]
    else
      filters
    end
    
    filters = if primitive = Keyword.get(opts, :primitive) do
      name = primitive |> to_string() |> String.split(".") |> List.last()
      ["primitive: #{name}" | filters]
    else
      filters
    end
    
    filters = if in_graph = Keyword.get(opts, :in_graph) do
      ["in graph: #{in_graph}" | filters]
    else
      filters
    end
    
    if filters != [] do
      " matching " <> Enum.join(filters, ", ")
    else
      ""
    end
  end

  defp format_element_detailed(elem) do
    type_info = if primitive_name = elem.type do
      name = primitive_name |> to_string() |> String.split(".") |> List.last()
      "#{name}"
    else
      "unknown"
    end
    
    semantic_info = if map_size(elem.semantic) > 0 do
      type = Map.get(elem.semantic, :type, "custom")
      " (#{type})"
    else
      ""
    end
    
    content_info = if elem.content do
      preview = elem.content |> String.slice(0, 30)
      " - \"#{preview}#{if String.length(elem.content) > 30, do: "...", else: ""}\""
    else
      ""
    end
    
    "#{type_info}#{semantic_info}#{content_info}"
  end

  defp suggest_available_options(opts) do
    # This would show what options are actually available
    # For now, just show a helpful message
    IO.puts("\n💡 Try:")
    IO.puts("  • find_element(type: :text_buffer)")
    IO.puts("  • find_element(role: :button)")
    IO.puts("  • find_element(primitive: Scenic.Primitive.Text)")
    IO.puts("  • hierarchy()  # Show graph structure")
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================
  
  
  
  defp show_available_types(entries) do
    types = entries
      |> Enum.flat_map(fn {_, data} -> Map.keys(data.by_type) end)
      |> Enum.uniq()
      |> Enum.sort()
    
    if types != [] do
      IO.puts("\nAvailable types: #{Enum.join(types, ", ")}")
    end
  end
  
  defp get_type_icon(type) do
    case type do
      :text_buffer -> "📝"
      :button -> "🔘"
      :menu -> "📂"
      :menu_item -> "📄"
      :text_input -> "✏️"
      :list -> "📋"
      :checkbox -> "☑️"
      :radio -> "⭕"
      :slider -> "🎚️"
      :dropdown -> "📥"
      _ -> "🏷️"
    end
  end
  
  defp format_size({width, height}), do: "#{width}×#{height}"
  defp format_size(_), do: "unknown"
  
  defp short_id(id) when is_binary(id) and byte_size(id) > 12 do
    String.slice(id, 0, 8) <> "..."
  end
  defp short_id(id), do: to_string(id)
  
  defp get_viewport(viewport) when is_struct(viewport, ViewPort), do: {:ok, viewport}
  defp get_viewport(name) when is_atom(name) do
    case Process.whereis(name) do
      nil -> {:error, "ViewPort #{inspect(name)} not found"}
      pid -> ViewPort.info(pid)
    end
  end
  defp get_viewport(pid) when is_pid(pid), do: ViewPort.info(pid)
  
  # ============================================================================
  # Backwards Compatibility - Deprecated Functions
  # ============================================================================
  
  @doc false
  @deprecated "Scene hierarchy not available through public API"
  def scene_tree(_viewport_name \\ :main_viewport) do
    IO.puts("⚠️  Scene hierarchy is not available through the public ViewPort interface")
    IO.puts("Use inspect_viewport() to see graphs and semantic content instead")
  end
  
  @doc false  
  @deprecated "Use inspect_viewport/1 instead"
  def inspect_app(viewport_name \\ :main_viewport) do
    inspect_viewport(viewport: viewport_name)
  end
  
  @doc false
  def list_graphs(viewport_name \\ :main_viewport) do
    inspect_viewport(viewport: viewport_name, show: :graphs)
  end
  
  @doc false
  def semantic_summary(viewport_name \\ :main_viewport) do
    inspect_viewport(viewport: viewport_name, show: :semantic)
  end
  
  @doc false
  def find_semantic(type, viewport_name \\ :main_viewport) do
    find(type, viewport_name)
  end
  
  @doc false
  def show_semantic(viewport_name \\ :main_viewport) do
    semantic(viewport_name)
  end
  
  @doc false
  def inspect_scene(scene_id, viewport_name \\ :main_viewport) do
    IO.puts("📌 Note: Use inspect_viewport(graph: \"#{scene_id}\") for better output")
    inspect_viewport(viewport: viewport_name, graph: scene_id, verbose: true)
  end
  
  @doc false
  def inspect_graph(graph_key, viewport_name \\ :main_viewport) do
    inspect_viewport(viewport: viewport_name, graph: graph_key, verbose: true)
  end
end