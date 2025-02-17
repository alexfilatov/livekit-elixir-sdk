defmodule LiveKit.TestFormatter do
  @moduledoc """
  Custom formatter for test environment that properly handles binary data in logs.
  """

  def format(level, message, timestamp, _metadata) do
    # Skip formatting if message contains binary data
    if is_binary(message) and not String.valid?(message) do
      ""
    else
      # Use default formatting for valid strings
      "#{format_timestamp(timestamp)} [#{level}] #{message}\n"
    end
  end

  defp format_timestamp({date, {hour, minute, second, _millisecond}}) do
    :io_lib.format(
      "~4..0B-~2..0B-~2..0B ~2..0B:~2..0B:~2..0B",
      [date |> elem(0), date |> elem(1), date |> elem(2), hour, minute, second]
    )
    |> to_string()
  end
end
