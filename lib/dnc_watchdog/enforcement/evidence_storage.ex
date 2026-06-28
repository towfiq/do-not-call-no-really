defmodule DncWatchdog.Enforcement.EvidenceStorage do
  @moduledoc """
  Stores uploaded evidence files under `priv/static/uploads/evidence`.
  """

  @upload_root Path.join([:code.priv_dir(:dnc_watchdog), "static", "uploads", "evidence"])

  def upload_root, do: @upload_root

  @doc """
  Writes `binary` to disk and returns a web-relative storage path.
  """
  def store!(case_id, original_name, binary, _content_type \\ nil) do
    dir = Path.join([@upload_root, to_string(case_id)])
    File.mkdir_p!(dir)

    ext = Path.extname(original_name)
    stored_name = "#{System.unique_integer([:positive])}#{ext}"
    absolute_path = Path.join(dir, stored_name)
    File.write!(absolute_path, binary)

    web_path = Path.join(["uploads", "evidence", to_string(case_id), stored_name])
    {web_path, stored_name}
  end

  def public_url(storage_path), do: "/" <> storage_path

  def absolute_path(%{storage_path: storage_path}) when is_binary(storage_path) do
    Path.join([:code.priv_dir(:dnc_watchdog), "static", storage_path])
  end

  def read_file(%{storage_path: storage_path}) do
    path = absolute_path(%{storage_path: storage_path})

    case File.read(path) do
      {:ok, binary} -> {:ok, binary}
      {:error, reason} -> {:error, reason}
    end
  end

  def delete_file(%{storage_path: storage_path}) when is_binary(storage_path) do
    absolute = Path.join([:code.priv_dir(:dnc_watchdog), "static", storage_path])

    if File.exists?(absolute) do
      File.rm!(absolute)
    end

    :ok
  end

  def delete_file(_), do: :ok
end
