# Apitizer

Toolkit for simplifying the development of REST API's in Phoenix and Ecto.

## Usage

```elixir
defmodule MyAppWeb.QueryBuilders.UserBuilder do
  use Apitizer.QueryBuilder, schema: MyApp.Accounts.User
  import Ecto.Query

  attribute :id, sortable: true
  attribute :display_name
  attribute :email
  attribute :role
  attribute :timezone

  association :posts, MyApp.QueryBuilders.PostBuilder
end

defmodule MyAppWeb.UserController do
  use MyAppWeb, :controller
  alias LinkerWeb.QueryBuilders.UserBuilder

  def index(conn, _params, _user) do
    json(conn, UserBuilder.paginate(conn))
  end

  def show(conn, %{"id" => id}, _user) do
    json(conn, UserBuilder.one!(conn, id))
  end
end
```

## TODO

- [X] Add more operators to the filter parser, keep some in reserve (such as
      "search" and other common, custom logic).
      ["search", "contains", "like", "ilike"]
- [ ] Add ability for custom preload
- [X] Add ability for custom sorting
- [X] It should be possible to overwrite an operator.
- [ ] Generate documentation from a query builder.
  - Expose through an endpoint in both HTML/JSON format?
  - Generate all at compile-time to basically just serve static html?
- [ ] Write documentation
- [X] Allow the querybuilder to be used to _just_ build the query, not execute it on
      the repo & generating a response.
- [X] Add hooks for permission checks:
  - [X] Can user apply filter?
  - [X] Can user perform this sort?
  - [X] Can user see certain attributes?
- [X] Add hooks throughout the building process
  - [X] before/after adding filters
  - [X] before/after adding preload
  - [X] before/after adding select
  - [X] before/after adding sort
- [X] Add support for pagination. Custom paginators? Behaviour? Protocol?
- [ ] Maybe implement some defaults for popular pagination libraries? Scivener?
- [X] Add maxdepth for includes.
- [X] Allow Repo to be configured once (bit of a pain to do it for every module.)
      Three levels of repo definition, in order of priority: argument > module > config
- [X] Allow select_key, sort_key and filter_key to be defined in the config.
- [ ] Filters on preload
- [ ] Add {asc,desc}_nulls_{first,last} to the parser & builder. Also update the
      typedocs in QueryBuilder & Parser.
- [X] Respect the `sortable` field on an attribute.
- [ ] Raise compile warning (not error) when transform function is defined for
      undefined attribute/assoc.
