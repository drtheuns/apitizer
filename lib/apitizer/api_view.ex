defmodule Apitizer.ApiView do
  @moduledoc """
  The ApiView specifies behaviour and implementation for a view that supports
  JSON rendering with includes.

  ## Includes

  Includes allow clients of your API to get nested data. For example, if we have
  a Post model with many Comments, it might make sense to return both in one API
  call. Includes allow the client to specify an `includes` query parameter which
  specifies the related resources they want to include. The call to posts might
  look like:

      `GET /posts/1?include=comments`

  Which might return something like:

  ```json
  {
    "data": {
      "id": 1,
      "title": "Our Clickbait Post Title",
      "body": "...",
      "comments": [
        {
          "id": 1,
          "body": "I fell for the bait!"
        }
      ]
    }
  }
  ```

  In order to support this on the backend, we need to implement a couple of
  things:

      * A mapping between request include to relationship name on the model. We
        need to be able to turn "comments" into something our data model
        understands. This is needed for eager loading the related data.
      * A mapping between request include to view module. We need to know which
        module can render some include.

  These two mappings are located in two different places. The preload mapping is
  placed in the schema module. For example, our Post module:

  ```elixir
  defmodule MyApp.Post do
    use Ecto.Schema
    @behaviour Apitizer.Includable

    schema "posts" do
      field :title, :string
      field :body, :string
      has_many :comments, Comment
    end

    # This is the mapping for the preloading.
    @impl Apitizer.Includable
    def include("comments"), do: :comments
    def include(_), do: nil
  end
  ```

  The view itself holds the mapping for the related views:

  ```elixir
  defmodule MyApp.PostView do
    use MyApp, :view
    use Apitizer.ApiView

    def render("show.json", %{post: post} = assigns) do
      %{data: render_one_with_includes(post, __MODULE__, "post.json", assigns)}
    end

    def render("post.json", %{post: post}) do
      %{
        id: post.id,
        title: post.title,
        body: post.body
      }
    end

    # Mapping of include -> view
    def include("comments", _post, _assigns), do: CommentView
    def include(_, _, _), do: nil
  end
  ```

  Your application now understands how things are related, but we still haven't
  done anything with the query parameters, so this won't do anything yet. To
  automatically parse the query parameters to something Apitizer understands,
  you can add the following to your router. Refer to `Apitizer.RequestParser`
  for more information.

  ```elixir
  pipeline :api do
    plug(:accepts, ["json"])
    plug(Apitizer.RequestParser)
  end
  ```

  At this point Apitizer will attempt to render a resource with its includes,
  but we're still missing one critical part: to actually get the data and
  preload the includes. To get the data:

  ```elixir
  defmodule MyApp.Blog do
    def get_post!(id, preload \\ []) do
      Post
      |> Repo.get!(id)
      |> Repo.preload(preload)
    end
  end
  ```

  We can then call this from our controller, as usual:

  ```elixir
  defmodule MyApp.PostController do
    use MyApp, :controller
    import Apitizer.Helpers, only: [to_preload: 2]

    def show(conn, %{"id" => id}) do
      post = MyApp.Blog.get_post!(id, to_preload(conn, MyApp.Post))
      render(conn, "show.json", post: post)
    end
  end
  ```

  See `Apitizer.Helpers.to_preload/2` for more information.

  With all of these steps combined, we're now able to render the "comments"
  include from the example. Apitizer also supports arbitrarily nested includes,
  so if we also wanted the author of the post as well as the author of each
  comment, the client can request this as:

      `GET /posts/1?include=author,comments.author`

  To render this response, all you need to do is update the preload and view
  mappings for all the resources in question.

  ## View mapping options

  The include mapping in the view supports a couple of formats to offer some
  more control over the final response.

      * `{CommentView, options}`
      * `CommentView`

  These are the most common types of includes. They simply defer loading of a
  resource to another view. For the accepted options, see below.

      * `{:merge, CommentView, options}`
      * `{:merge, CommentView}`

  This will merge the result of the include into the main response. Merge
  includes can be useful when you want to reduce the response size. Clients that
  need the extra data can simple add the include. For accepted options, see
  below.

      * `{:merge, %{key: value}}`
      * `{%{key: value}, options}`
      * `%{key: value}`

  Just like how you can use another view to render an include, you can also
  simply return a rendered map.

  ### Options

      * `:as` the key on which the rendered child include will be placed. If you
        wanted to render the post's author as "post_author" instead of just
        author, you could do so with: `{AuthorView, as: :user}`.
      * `:template` the view template to use when rendering the include. By
        default this will use the resource name of the view, e.g. `CommentView`
        will use `"comment.json"`.
  """

  alias Apitizer.IncludeTree

  @typedoc """
  The resource that was rendered.

  Usually this will be a struct that was fetched by Ecto.
  """
  @type resource :: map()

  @typedoc """
  The assigns as passed to the Phoenix view.
  """
  @type assigns :: map()

  @type view_opt :: {:as, atom()} | {:template, String.t()}
  @type view_opts :: [view_opt]

  defmacro __using__(_env) do
    quote do
      import Apitizer.ApiView

      def render_includes(rendered, resource, assigns),
        do: render_includes(__MODULE__, rendered, resource, assigns)

      @doc """
      Renders a single resource with the includes.

      The same as `Phoenix.View.render_one/4`.

      The `:as` key is cleared for child resources.
      """
      def render_one_with_includes(resource, view, template, assigns \\ %{})
      def render_one_with_includes(nil, _view, _template, _assigns), do: nil

      def render_one_with_includes(resource, view, template, assigns) do
        assigns = assign_resource(to_map(assigns), view, resource)

        view
        |> render(template, assigns)
        |> render_includes(resource, Map.delete(assigns, :as))
      end

      @doc """
      Renders many resources with their includes.

      The same as `Phoenix.View.render_many/4`.

      The `:as` key is cleared for child resources.
      """
      def render_many_with_includes(collection, view, template, assigns) do
        assigns = to_map(assigns)

        Enum.map(collection, fn resource ->
          render_one_with_includes(resource, view, template, assigns)
        end)
      end

      defp assign_resource(assigns, view, resource) do
        as = Map.get(assigns, :as) || view.__resource__
        Map.put(assigns, as, resource)
      end

      defp to_map(assigns) when is_map(assigns), do: assigns
      defp to_map(assigns) when is_list(assigns), do: :maps.from_list(assigns)
    end
  end

  @doc """
  Specifies which module is capable of rendering an include.

  The first key specifies the include as is given in the request. The resource
  and assigns might be used to, for example, determine the include based on the
  logged in user.

  The response should always include at least two keys:

    * `module`: the view module to render the include.

  If you return `:merge` as first key, then the rendered result will be merged
  with the "parent" resource.

  While the module based response is preferred, it's also possible to just
  return the rendered map as a result.

  ## Examples

      def include("comments", _resource, _assigns), do: {CommentView, :comment}

  Only allow author include if the logged in user _is_ the author.

      def include("author", %{author_id: user_id}, %{current_user: %{id: user_id}}), do: {UserView, :author}
  """
  @callback include(String.t(), resource, assigns) ::
              {module, view_opts}
              | module()
              | {:merge, module(), view_opts}
              | {:merge, module()}
              | {map, view_opts}
              | map()
              | {:merge, map()}
              | nil

  @doc """
  This is the primary entrypoint for rendering the includes and should be called
  in your render function.

  ## Example

      def render("user.json", %{user: user} = assigns) do
        %{
          id: user.id,
          name: user.name
        }
        |> render_includes(user, assigns)
      end
  """
  @spec render_includes(module(), map(), resource, assigns) :: map()
  def render_includes(module, response, resource, %{includes: includes} = assigns) do
    # We can only do something meaningful if we have an include tree.
    # If the user changed the includes we can't do anything here.
    case includes do
      %IncludeTree{} -> render_include_tree(module, response, resource, assigns, includes)
      _ -> response
    end
  end

  def render_includes(_module, response, _resource, _assigns), do: response

  defp render_include_tree(module, response, resource, assigns, tree) do
    # This is all really quite verbose. Maybe introduce a context object and
    # pass this around? Then the case could become a function.
    Enum.reduce(tree.children, response, fn {include, child_tree}, acc ->
      case get_include_view(module, include, resource, assigns) do
        {:merge, child_view, opts} when is_atom(child_view) and is_list(opts) ->
          rendered = render_child_view(child_view, include, resource, assigns, child_tree, opts)

          Map.merge(acc, rendered)

        {:merge, child_view} when is_atom(child_view) ->
          rendered = render_child_view(child_view, include, resource, assigns, child_tree)
          Map.merge(acc, rendered)

        {:merge, rendered_include} when is_map(rendered_include) ->
          Map.merge(acc, rendered_include)

        {child_view, opts} when is_atom(child_view) and is_list(opts) ->
          rendered = render_child_view(child_view, include, resource, assigns, child_tree, opts)
          key = Keyword.get(opts, :as, include)

          Map.put(acc, key, rendered)

        child_view when is_atom(child_view) and child_view != nil ->
          rendered = render_child_view(child_view, include, resource, assigns, child_tree)
          Map.put(acc, include, rendered)

        {rendered_include, opts} when is_map(rendered_include) and is_list(opts) ->
          key = Keyword.get(opts, :as, include)
          Map.put(acc, key, rendered_include)

        rendered_include when is_map(rendered_include) ->
          Map.put(acc, include, rendered_include)

        _ ->
          acc
      end
    end)
  end

  defp get_include_view(module, include, resource, assigns) do
    if function_exported?(module, :include, 3) do
      module.include(include, resource, assigns)
    else
      nil
    end
  end

  defp render_child_view(view_module, include, resource, assigns, child_tree, opts \\ []) do
    if function_exported?(resource.__struct__, :include, 1) do
      case Map.get(resource, resource.__struct__.include(include)) do
        %Ecto.Association.NotLoaded{} ->
          nil

        child_resource ->
          assigns = Map.put(assigns, :includes, child_tree)
          key = Keyword.get(opts, :template, "#{view_module.__resource__}.json")
          render_one_or_many(view_module, child_resource, key, assigns)
      end
    else
      nil
    end
  end

  defp render_one_or_many(view_module, resource, key, assigns) when is_list(resource) do
    view_module.render_many_with_includes(resource, view_module, key, assigns)
  end

  defp render_one_or_many(view_module, resource, key, assigns) do
    view_module.render_one_with_includes(resource, view_module, key, assigns)
  end

  @doc """
  Set a value on the map when `condition` is true.

  Can be useful to set keys based on, for example, the logged in user's role.

  ## Example

      iex> put_when(%{}, true, :email, "john@doe.com")
      %{email: "john@doe.com}
      iex> put_when(%{}, false, :email, "john@doe.com")
      %{}
      iex> put_when(%{}, false, :email, "john@doe.com", "redacted")
      %{email: "redacted"}
  """
  @spec put_when(map(), boolean(), atom() | String.t(), value :: any(), default :: any()) :: map()
  def put_when(map, condition, key, value, default \\ nil)
  def put_when(map, true, key, value, _), do: Map.put(map, key, value)
  def put_when(map, false, _, _, nil), do: map
  def put_when(map, false, key, _, default), do: Map.put(map, key, default)

  @doc """
  Merge a map of values only when some condition is true.

  This is primarily useful in the `render` function in your view.

  ## Example

      iex> merge_when(%{}, true, %{email: "john@doe.com})
      %{email: "john@doe.com}
  """
  def merge_when(source_map, true, value_map), do: Map.merge(source_map, value_map)
  def merge_when(source_map, false, _value_map), do: source_map
end
