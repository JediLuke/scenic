#
#  Created by Boyd Multerer on 2021-09-08
#  Copyright 2021 Kry10 Limited
#

defmodule Scenic.Driver.KeyMap do
  @moduledoc """
  Behaviour and support for mapping key press/repeat input to codepoints
  """

  # @doc """
  # Map of current key state. A key with a value of 1 is pressed. A key with
  # a value of 0 or that is missing from the map is not pressed.

  # Some keys have multiple states and may be values higher than 1. You get
  # to interpret that as appropriate.
  # """
  @type keys :: %{atom => boolean}

  @doc """
  Translate a key to a codepoint, which is really just a string.

  The first time this is called, state is nil. After that you can return
  any state that makes sense and it will be passed back on the next call.

  If the mapping is successful, i.e. the key press results in a valid character,
  Then this function should return `{ :ok, codepoint, state }`. The returned
  codepoint will be sent on to the ViewPort as a codepoint intput event.

  If the key press does not map to a string (this is common), then the function
  should return `{ :ok, nil, state }`. This will not result in a codepoint input
  being sent to the ViewPort.

  If the data makes no sense at all, then you can return `{ :error, error_msg, state }`.
  This will not send a codepoint input, but will log the error message, which should
  be a string.
  """
  @callback map_key(key :: atom, value :: non_neg_integer, keys :: keys(), state :: any) ::
              {:ok, nil, state :: any}
              | {:ok, codepoint :: String.t(), state :: any}
              | {:error, msg :: String.t(), state :: any}

  @doc """
  Is the caps lock enabled?

  Returns true if any shift key or the caps lock is pressed or active.
  """
  @spec caps_lock?(keys :: keys) :: boolean
  def caps_lock?(keys) do
    is_pressed?(keys[:virt_caps_lock])
  end

  @doc """
  Is the current set of keys shifted?

  Returns true if any shift key or the caps lock is pressed or active.
  """
  @spec shift?(keys :: keys) :: boolean
  def shift?(keys) do
    is_pressed?(keys[:key_leftshift]) ||
      is_pressed?(keys[:key_rightshift])
  end

  @doc """
  Is any alt key pressed?
  """
  @spec alt?(keys :: keys) :: boolean
  def alt?(keys) do
    is_pressed?(keys[:key_leftalt]) ||
      is_pressed?(keys[:key_rightalt])
  end

  @doc """
  Is any ctrl key pressed?
  """
  @spec ctrl?(keys :: keys) :: boolean
  def ctrl?(keys) do
    is_pressed?(keys[:key_leftctrl]) ||
      is_pressed?(keys[:key_rightctrl])
  end

  @doc """
  Is any meta key pressed? This is usually the command button.
  """
  @spec meta?(keys :: keys) :: boolean
  def meta?(keys) do
    is_pressed?(keys[:key_leftmeta]) ||
      is_pressed?(keys[:key_rightmeta])
  end

  @doc """
  Generate the list of pressed modifier keys
  """
  @spec mods(keys :: keys) :: boolean
  def mods(keys) do
    []
    |> add_if_set(:meta, meta?(keys))
    |> add_if_set(:alt, alt?(keys))
    |> add_if_set(:ctrl, ctrl?(keys))
    |> add_if_set(:shift, shift?(keys))
    |> add_if_set(:caps_lock, caps_lock?(keys))
  end

  defp is_pressed?(nil), do: false
  defp is_pressed?(0), do: false
  defp is_pressed?(_), do: true

  defp add_if_set(list, value, true), do: [value | list]
  defp add_if_set(list, _value, false), do: list
end
