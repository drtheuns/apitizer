# Apitizer

Toolkit for simplifying the development of REST API's in Phoenix and Ecto.

# TODO

- [X] Add ability for custom preload
- [ ] Add ability for custom filter (operator)
- [ ] Add ability for custom sorting
- [ ] It should be possible to overwrite an operator.
- [ ] Generate documentation from a query builder.
  - Expose through an endpoint in both HTML/JSON format?
  - Generate all at compile-time to basically just serve static html?
- [ ] Write documentation
- [ ] Allow the querybuilder to be used to _just_ build the query, not execute it on
      the repo & generating a response.
- [ ] Add hooks for permission checks:
  - [ ] Can user apply filter?
  - [ ] Can user perform this sort?
  - [ ] Can user see certain attributes?
- [ ] Add hooks throughout the building process
  - [ ] before/after adding filters
  - [ ] before/after adding preload
  - [ ] before/after adding select
  - [ ] before/after applying transformations
- [ ] Add support for pagination. Custom paginators? Behaviour? Protocol?
      Maybe implement some defaults for popular pagination libraries? Scivener?
- [ ] Add maxdepth for includes.
- [ ] Allow Repo to be configured once (bit of a pain to do it for every module.)
      Three levels of repo definition, in order of priority: argument > module > config
- [ ] Allow select_key and filter_key to be defined in the config.
