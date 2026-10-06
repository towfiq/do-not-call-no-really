defmodule DncWatchdog.Enforcement.SosLookup do
  @moduledoc """
  Looks up a defendant's registered agent on the state's business-entity site.

  Secretary of State portals often block non-browser clients. Callers should
  still open `search_page/2` so the user can confirm the record, and treat
  incoming call numbers as a fallback business phone (SC-100 requires one).
  """

  alias DncWatchdog.Enforcement.LegalEntity

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " <>
                "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

  @registries %{
    "CA" => %{
      name: "California Secretary of State (BizFile)",
      url: "https://bizfileonline.sos.ca.gov/search/business"
    },
    "DE" => %{
      name: "Delaware Division of Corporations",
      url: "https://icis.corp.delaware.gov/Ecorp/EntitySearch/NameSearch.aspx"
    },
    "FL" => %{
      name: "Florida Division of Corporations (Sunbiz)",
      url: "https://search.sunbiz.org/Inquiry/CorporationSearch/ByName"
    },
    "IL" => %{
      name: "Illinois Secretary of State",
      url: "https://apps.ilsos.gov/businessentitysearch/"
    },
    "NV" => %{
      name: "Nevada Secretary of State",
      url: "https://esos.nv.gov/EntitySearch/OnlineEntitySearch"
    },
    "NY" => %{
      name: "New York Department of State",
      url: "https://apps.dos.ny.gov/publicInquiry/"
    },
    "TX" => %{
      name: "Texas Secretary of State",
      url: "https://www.sos.state.tx.us/corp/sosda/index.shtml"
    },
    "WA" => %{
      name: "Washington Secretary of State",
      url: "https://ccfs.sos.wa.gov/"
    },
    "GB" => %{
      name: "UK Companies House",
      url: "https://find-and-update.company-information.service.gov.uk/search"
    }
  }

  @ca_search_url "https://bizfileonline.sos.ca.gov/api/Records/businesssearch"
  @ca_detail_url "https://bizfileonline.sos.ca.gov/api/FilingDetail/business"

  @doc """
  Public search page for the entity's state of formation.
  """
  def search_page(state, name, opts \\ []) do
    state = lookup_region(state, Keyword.get(opts, :country))
    name = present(name) || ""

    case Map.get(@registries, state) do
      %{name: registry, url: url} ->
        %{state: state, name: registry, url: registry_url(url, name), query: name}

      _ ->
        query =
          [name, state, registry_query_terms(state)]
          |> Enum.reject(&(&1 in [nil, ""]))
          |> Enum.join(" ")

        %{
          state: state,
          name: "State business-entity search",
          url: "https://www.google.com/search?q=#{URI.encode_www_form(query)}",
          query: name
        }
    end
  end

  @doc """
  Attempt a structured lookup. Returns `{:ok, attrs}` or `{:error, reason}`.
  """
  def lookup(name, state, opts \\ []) do
    name = present(name)
    state = lookup_region(state, Keyword.get(opts, :country))
    client = Keyword.get(opts, :http_client, &http_request/4)

    cond do
      name in [nil, ""] ->
        {:error, :missing_name}

      state == "CA" ->
        lookup_california(name, client)

      true ->
        {:error, :open_registry}
    end
  end

  @doc """
  Merge SOS results and a suggested phone into an existing entity without
  wiping a mailing address the user already entered.
  """
  def merge_into_entity(entity, sos_attrs, opts \\ []) do
    entity = entity || %LegalEntity{}
    sos_attrs = stringify_keys(sos_attrs)
    suggested_phone = Keyword.get(opts, :suggested_phone)

    agent_name =
      first_present([
        sos_attrs["agent_name"],
        blank_to_nil(entity.agent_name),
        blank_to_nil(entity.attn)
      ])

    %{}
    |> maybe_put(
      "phone",
      first_present([sos_attrs["phone"], blank_to_nil(entity.phone), suggested_phone])
    )
    |> maybe_put("agent_name", agent_name)
    |> maybe_put(
      "agent_title",
      first_present([
        sos_attrs["agent_title"],
        blank_to_nil(entity.agent_title),
        if(agent_name, do: "Registered Agent")
      ])
    )
    |> maybe_put(
      "agent_street",
      first_present([sos_attrs["agent_street"], blank_to_nil(entity.agent_street)])
    )
    |> maybe_put(
      "agent_city",
      first_present([sos_attrs["agent_city"], blank_to_nil(entity.agent_city)])
    )
    |> maybe_put(
      "agent_state",
      first_present([sos_attrs["agent_state"], blank_to_nil(entity.agent_state)])
    )
    |> maybe_put(
      "agent_zip",
      first_present([sos_attrs["agent_zip"], blank_to_nil(entity.agent_zip)])
    )
    |> maybe_put(
      "agent_phone",
      first_present([sos_attrs["agent_phone"], blank_to_nil(entity.agent_phone)])
    )
    |> maybe_put(
      "sos_entity_number",
      first_present([sos_attrs["sos_entity_number"], blank_to_nil(entity.sos_entity_number)])
    )
    |> maybe_put("sos_url", first_present([sos_attrs["sos_url"], blank_to_nil(entity.sos_url)]))
    |> maybe_put("attn", first_present([blank_to_nil(entity.attn), sos_attrs["agent_name"]]))
    |> maybe_fill_address(entity, sos_attrs)
    |> maybe_put(
      "country",
      first_present([sos_attrs["country"], blank_to_nil(entity.country)])
    )
    |> maybe_put(
      "legal_name",
      first_present([
        blank_to_nil(entity.legal_name),
        sos_attrs["legal_name"],
        Keyword.get(opts, :legal_name)
      ])
    )
    |> maybe_put("entity_type", blank_to_nil(entity.entity_type) || "company")
  end

  defp maybe_fill_address(attrs, entity, sos_attrs) do
    if present(entity.street) do
      attrs
    else
      attrs
      |> maybe_put("street", sos_attrs["street"])
      |> maybe_put("city", sos_attrs["city"])
      |> maybe_put("state", sos_attrs["state"])
      |> maybe_put("zip", sos_attrs["zip"])
      |> maybe_put("country", sos_attrs["country"])
    end
  end

  defp lookup_california(name, client) do
    body =
      Jason.encode!(%{
        "SEARCH_VALUE" => String.upcase(name),
        "SEARCH_FILTER_TYPE_ID" => "0",
        "SEARCH_TYPE_ID" => "1",
        "FILING_TYPE_ID" => "",
        "STATUS_ID" => "",
        "FILING_DATE" => %{"start" => nil, "end" => nil},
        "CORP_TYPE_ID" => "",
        "LOCATION_ID" => ""
      })

    headers = [
      {"accept", "application/json"},
      {"content-type", "application/json"},
      {"user-agent", @user_agent},
      {"origin", "https://bizfileonline.sos.ca.gov"},
      {"referer", "https://bizfileonline.sos.ca.gov/search/business"}
    ]

    with {:ok, %{status: 200, body: search_body}} <- client.(:post, @ca_search_url, headers, body),
         {:ok, search_json} <- decode(search_body),
         {:ok, record} <- pick_california_record(search_json, name),
         record_id when is_binary(record_id) <- california_record_id(record),
         {:ok, %{status: 200, body: detail_body}} <-
           client.(:get, "#{@ca_detail_url}/#{record_id}/false", headers, nil),
         {:ok, detail_json} <- decode(detail_body) do
      {:ok, parse_california_detail(detail_json, record)}
    else
      {:ok, %{status: status}} when status in [401, 403, 429] ->
        {:error, :blocked}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :not_found}
    end
  end

  @doc false
  def pick_california_record(json, name) when is_map(json) do
    rows = json["rows"] || json["ROWS"] || %{}

    records =
      cond do
        is_map(rows) -> Map.values(rows)
        is_list(rows) -> rows
        true -> []
      end

    needle = normalize(name)

    match =
      Enum.find(records, fn row ->
        String.contains?(normalize(row_title(row)), needle)
      end)

    if match, do: {:ok, match}, else: {:error, :not_found}
  end

  @doc false
  def parse_california_detail(detail, record \\ %{}) do
    labels = drawer_pairs(detail)

    agent_name =
      first_present([
        label_value(labels, ~r/agent.*process|registered agent|agent name/i),
        get_in(record, ["AGENT_FULL_NAME"]),
        get_in(record, ["AGENT"])
      ])

    %{
      "legal_name" => first_present([label_value(labels, ~r/^entity name$/i), row_title(record)]),
      "sos_entity_number" =>
        first_present([
          label_value(labels, ~r/entity number|file number|record/i),
          california_record_id(record)
        ]),
      "status" => first_present([label_value(labels, ~r/^status$/i)]),
      "street" =>
        first_present([label_value(labels, ~r/entity address|principal address|street address/i)]),
      "city" => first_present([label_value(labels, ~r/^city$/i)]),
      "state" => first_present([label_value(labels, ~r/^state$/i), "CA"]),
      "zip" => first_present([label_value(labels, ~r/zip/i)]),
      "agent_name" => agent_name,
      "agent_title" =>
        first_present([
          label_value(labels, ~r/agent.*title|job title/i),
          if(agent_name, do: "Registered Agent")
        ]),
      "agent_street" => first_present([label_value(labels, ~r/agent.*street|agent.*address/i)]),
      "agent_city" => first_present([label_value(labels, ~r/agent.*city/i)]),
      "agent_state" => first_present([label_value(labels, ~r/agent.*state/i)]),
      "agent_zip" => first_present([label_value(labels, ~r/agent.*zip/i)]),
      "sos_url" => "https://bizfileonline.sos.ca.gov/search/business",
      "source" => "ca_bizfile"
    }
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> Map.new()
  end

  defp drawer_pairs(detail) when is_map(detail) do
    list = detail["DRAWER_DETAIL_LIST"] || detail["drawer_detail_list"] || []

    Enum.flat_map(List.wrap(list), fn
      %{"LABEL" => label, "VALUE" => value} -> [{to_string(label), stringify_value(value)}]
      %{"label" => label, "value" => value} -> [{to_string(label), stringify_value(value)}]
      _ -> []
    end)
  end

  defp drawer_pairs(_), do: []

  defp label_value(pairs, regex) do
    pairs
    |> Enum.find_value(fn {label, value} ->
      if Regex.match?(regex, label), do: present(value)
    end)
  end

  defp row_title(row) when is_map(row) do
    first_present([
      stringify_value(row["TITLE"]),
      row["ENTITY_NAME"],
      row["entity_name"],
      row["NAME"]
    ])
  end

  defp row_title(_), do: nil

  defp california_record_id(row) when is_map(row) do
    first_present([
      row["RECORD_NUM"],
      row["RECORD_ID"],
      row["entityId"],
      row["ENTITY_ID"]
    ])
  end

  defp california_record_id(_), do: nil

  defp stringify_value(value) when is_list(value) do
    value
    |> Enum.map(&stringify_value/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
    |> present()
  end

  defp stringify_value(value) when is_binary(value), do: present(value)
  defp stringify_value(value) when is_number(value), do: to_string(value)
  defp stringify_value(_), do: nil

  defp http_request(method, url, headers, body) do
    Finch.build(method, url, headers, body)
    |> Finch.request(DncWatchdog.Finch, receive_timeout: 15_000)
    |> case do
      {:ok, %Finch.Response{status: status, body: resp_body}} ->
        {:ok, %{status: status, body: resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode(body) when is_binary(body), do: Jason.decode(body)
  defp decode(body) when is_map(body), do: {:ok, body}
  defp decode(_), do: {:error, :invalid_json}

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp stringify_keys(_), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp first_present(values), do: Enum.find_value(values, &present/1)

  defp blank_to_nil(value), do: present(value)

  defp present(value) when value in [nil, ""], do: nil
  defp present(value) when is_binary(value), do: String.trim(value)
  defp present(value), do: value

  defp normalize(nil), do: ""

  defp normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, " ")
    |> String.trim()
  end

  defp registry_url(url, name) do
    if String.contains?(url, "company-information.service.gov.uk") and present(name) do
      url <> "?q=" <> URI.encode_www_form(name)
    else
      url
    end
  end

  defp registry_query_terms("GB"), do: "Companies House registered office"
  defp registry_query_terms(_), do: "secretary of state registered agent"

  defp lookup_region(state, country) do
    case LegalEntity.normalize_country(country) do
      "US" -> normalize_region(state)
      other -> normalize_region(other)
    end
  end

  defp normalize_region(nil), do: nil

  defp normalize_region(value) when is_binary(value) do
    case value |> String.trim() |> String.upcase() do
      "" ->
        nil

      region when region in ["GB", "UK", "ENG", "ENGLAND", "UNITED KINGDOM", "GREAT BRITAIN"] ->
        "GB"

      region ->
        region
    end
  end
end
