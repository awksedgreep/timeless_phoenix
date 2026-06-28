defmodule TimelessPhoenix.Identity do
  @moduledoc false

  @spec logger_metadata() :: keyword()
  def logger_metadata do
    identity = resolve()

    [
      {:"host.name", identity.host_name},
      {:"service.name", identity.service_name},
      host: identity.host_name,
      service: identity.service_name
    ]
  end

  @spec span_attributes() :: map()
  def span_attributes do
    identity = resolve()

    %{
      "host.name" => identity.host_name,
      "service.name" => identity.service_name
    }
  end

  @spec ensure_opentelemetry_resource() :: :ok
  def ensure_opentelemetry_resource do
    identity = resolve()

    resource =
      Application.get_env(:opentelemetry, :resource, [])
      |> merge_resource(identity)

    Application.put_env(:opentelemetry, :resource, resource)
  end

  @spec merge_resource(keyword() | map(), %{host_name: String.t(), service_name: String.t()}) ::
          keyword() | map()
  def merge_resource(resource, identity) when is_map(resource) do
    resource
    |> maybe_put_nested([:service, :name], identity.service_name)
    |> maybe_put_nested([:host, :name], identity.host_name)
  end

  def merge_resource(resource, identity) when is_list(resource) do
    resource
    |> keyword_put_new_nested([:service, :name], identity.service_name)
    |> keyword_put_new_nested([:host, :name], identity.host_name)
  end

  def merge_resource(_resource, identity) do
    [
      service: [name: identity.service_name],
      host: [name: identity.host_name]
    ]
  end

  @spec resolve() :: %{host_name: String.t(), service_name: String.t()}
  def resolve do
    %{
      service_name: resolve_service_name(),
      host_name: resolve_host_name()
    }
  end

  @spec resolve_service_name() :: String.t()
  def resolve_service_name do
    extract_resource_value(Application.get_env(:opentelemetry, :resource, []), ["service.name"]) ||
      System.get_env("OTEL_SERVICE_NAME") ||
      release_name() ||
      "unknown_service:elixir"
  end

  @spec resolve_host_name() :: String.t()
  def resolve_host_name do
    extract_resource_value(Application.get_env(:opentelemetry, :resource, []), ["host.name"]) ||
      System.get_env("HOSTNAME") ||
      hostname_from_node() ||
      inet_hostname() ||
      "unknown-host"
  end

  defp release_name do
    System.get_env("RELEASE_NAME") || System.get_env("REL_NAME")
  end

  defp hostname_from_node do
    case to_string(node()) do
      "nonode@nohost" -> nil
      node_name -> List.last(String.split(node_name, "@"))
    end
  end

  defp inet_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> List.to_string(hostname)
      _ -> nil
    end
  end

  defp extract_resource_value(resource, path) when is_map(resource) do
    do_extract_resource_value(resource, path)
  end

  defp extract_resource_value(resource, path) when is_list(resource) do
    resource
    |> Map.new()
    |> do_extract_resource_value(path)
  end

  defp extract_resource_value(_, _path), do: nil

  defp do_extract_resource_value(resource, [dotted_key]) do
    case Map.get(resource, dotted_key) do
      nil ->
        dotted_key
        |> String.split(".")
        |> get_nested_value(resource)

      value ->
        value
    end
  end

  defp get_nested_value([], value), do: value

  defp get_nested_value([segment | rest], resource) when is_map(resource) do
    case Map.get(resource, String.to_atom(segment)) || Map.get(resource, segment) do
      nil -> nil
      value -> get_nested_value(rest, value)
    end
  end

  defp get_nested_value([segment | rest], resource) when is_list(resource) do
    case Keyword.get(resource, String.to_atom(segment)) || list_get(resource, segment) do
      nil -> nil
      value -> get_nested_value(rest, value)
    end
  end

  defp get_nested_value(_segments, _resource), do: nil

  defp list_get(list, key) do
    case List.keyfind(list, key, 0) do
      {^key, value} -> value
      _ -> nil
    end
  end

  defp maybe_put_nested(resource, [parent, child], value) do
    case get_in(resource, [Access.key(parent, %{}), Access.key(child)]) do
      nil -> put_in(resource, [Access.key(parent, %{}), Access.key(child)], value)
      _ -> resource
    end
  end

  defp keyword_put_new_nested(keyword, [parent, child], value) do
    case Keyword.get(keyword, parent) do
      nil ->
        Keyword.put(keyword, parent, [{child, value}])

      nested when is_list(nested) ->
        Keyword.put(keyword, parent, Keyword.put_new(nested, child, value))

      nested when is_map(nested) ->
        Keyword.put(keyword, parent, Map.put_new(nested, child, value))

      _ ->
        keyword
    end
  end
end
