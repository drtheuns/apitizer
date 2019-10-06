defmodule Apitizer.ParserTest do
  use ExUnit.Case, async: true
  doctest Apitizer.Parser, import: true

  def filter(query) do
    Apitizer.Parser.parse_filter(query)
  end

  def select(query) do
    Apitizer.Parser.parse_select(query)
  end

  def sort(query) do
    Apitizer.Parser.parse_sort(query)
  end

  describe "filter" do
    test "it should parse comparison expressions" do
      assert filter("and(student.eq.true, grade.gte.90)") ==
               {:and, [{:eq, "student", true}, {:gte, "grade", 90}]}

      assert filter("and(name.eq.john,grade.in.(1,2,3))") ==
               {:and, [{:eq, "name", "john"}, {:in, "grade", [1, 2, 3]}]}
    end

    test "it should accept recursive and/or expressions" do
      assert filter("or(role.eq.student,and(course.eq.English Literature,name.eq.John))") ==
               {:or,
                [
                  {:eq, "role", "student"},
                  {:and, [{:eq, "course", "English Literature"}, {:eq, "name", "John"}]}
                ]}

      assert filter(
               "and(something.eq.wow, switch.eq.true, or(value.gte.5,value.lte.2), and(field.eq.true, name.eq.null))"
             ) ==
               {:and,
                [
                  {:eq, "something", "wow"},
                  {:eq, "switch", true},
                  {:or, [{:gte, "value", 5}, {:lte, "value", 2}]},
                  {:and, [{:eq, "field", true}, {:eq, "name", nil}]}
                ]}

      assert filter("and(or(grade.gte.9,and(grade.lte.3,name.eq.john)))") ==
               {:and,
                [
                  {:or, [{:gte, "grade", 9}, {:and, [{:lte, "grade", 3}, {:eq, "name", "john"}]}]}
                ]}
    end

    test "it should accept empty lists" do
      assert filter("and(id.in.())") == {:and, [{:in, "id", []}]}
    end

    test "it should remove empty and/or expressions" do
      assert filter("and()") == []
      assert filter("or()") == []
      assert filter("and(id.eq.5,or())") == {:and, [{:eq, "id", 5}]}
    end

    test "it should accept quoted expressions" do
      assert filter(~S{and(field.in.("hello, world", "5"))}) ==
               {:and, [{:in, "field", ["hello, world", "5"]}]}

      assert filter(~S{and(name.eq."Doe, John", id.eq."5")}) ==
               {:and, [{:eq, "name", "Doe, John"}, {:eq, "id", "5"}]}
    end

    test "it should allow for escaping of quotes within quoted expressions" do
      assert filter(~S{and(name.eq."John \" Doe")}) == {:and, [{:eq, "name", "John \" Doe"}]}

      assert filter(~S{and(name.in.("Wow\"", "Doe"))}) ==
               {:and, [{:in, "name", ["Wow\"", "Doe"]}]}
    end

    test "AND is assumed when neither and|or is given" do
      assert filter(~S{id.eq.5}) == {:and, [{:eq, "id", 5}]}
      assert filter(~S{id.eq.5,priority.gte.4}) == {:and, [{:eq, "id", 5}, {:gte, "priority", 4}]}

      assert filter(~S{priority.eq.5,or(id.eq.4,id.eq.5)}) ==
               {:and, [{:eq, "priority", 5}, {:or, [{:eq, "id", 4}, {:eq, "id", 5}]}]}

      assert filter(~S{priority.eq.5,or(id.eq.4,and(id.eq.5,priority.gte.4))}) ==
               {:and,
                [
                  {:eq, "priority", 5},
                  {:or, [{:eq, "id", 4}, {:and, [{:eq, "id", 5}, {:gte, "priority", 4}]}]}
                ]}
    end

    test "a field of * should be considered the model/resource itself" do
      assert filter(~S{*.search.#wow}) == {:and, [{:search, :*, "#wow"}]}
    end
  end

  describe "casting" do
    test "integers should be cast to integers" do
      {:and, [{:in, "id", values}]} = filter("and(id.in.(1,2,3))")

      Enum.each(values, fn value ->
        assert is_integer(value)
      end)
    end

    test "decimal numbers (with a .) should be cast to floats" do
      assert filter("and(grade.eq.4.5)") == {:and, [{:eq, "grade", 4.5}]}

      assert filter("and(grade.in.(5.5, 6.5, 7.5, 8.5, 9.5))") ==
               {:and, [{:in, "grade", [5.5, 6.5, 7.5, 8.5, 9.5]}]}
    end

    test "it should cast boolean expression for neq and eq" do
      assert filter("and(is_visible.eq.true,is_published.neq.false)") ==
               {:and, [{:eq, "is_visible", true}, {:neq, "is_published", false}]}

      assert filter("and(updated_at.eq.null,published_at.neq.null)") ==
               {:and, [{:eq, "updated_at", nil}, {:neq, "published_at", nil}]}
    end

    test "quoted expressions should not be cast" do
      assert filter(~S{and(is_visible.eq."true")}) == {:and, [{:eq, "is_visible", "true"}]}
      assert filter(~S{and(is_visible.neq."false")}) == {:and, [{:neq, "is_visible", "false"}]}

      assert filter(~S{and(id.in.("1,2,3", "true", "null"))}) ==
               {:and, [{:in, "id", ["1,2,3", "true", "null"]}]}
    end
  end

  describe "select" do
    test "should parse simple fields" do
      assert select("id,name,title") == ["id", "name", "title"]
      assert select("id, name , title") == ["id", "name", "title"]
    end

    test "it should accept associations" do
      assert select("id,name,comments(id,body)") == [
               "id",
               "name",
               {:assoc, "comments", ["id", "body"]}
             ]
    end

    test "should accept aliases" do
      expected = [{:alias, "id", "identifier"}, {:alias, "some_field", "someField"}, "title"]
      assert select("identifier:id,someField:some_field  , title") == expected
    end

    test "aliases should work for associations" do
      assert select("replies:comments(id,body)") == [
               {:assoc, {:alias, "comments", "replies"}, ["id", "body"]}
             ]
    end

    test "it should accept select *" do
      assert select("*") == [:all]
      assert select("*,comments(*)") == [:all, {:assoc, "comments", [:all]}]
    end

    test "it should accept nested assocations with aliases" do
      assert select("*,comments(*,author:user(id, name, contact:email, posts(id)))") == [
               :all,
               {:assoc, "comments",
                [
                  :all,
                  {:assoc, {:alias, "user", "author"},
                   [
                     "id",
                     "name",
                     {:alias, "email", "contact"},
                     {:assoc, "posts", ["id"]}
                   ]}
                ]}
             ]
    end
  end

  describe "sort" do
    test "should accept just a field and default to :asc" do
      assert sort("field") == [{:asc, "field"}]
    end

    test "should allow multiple fields" do
      assert sort("field1,field2,field3") == [
               {:asc, "field1"},
               {:asc, "field2"},
               {:asc, "field3"}
             ]
    end

    test "should allow asc|desc to be prepended" do
      assert sort("field.asc") == [{:asc, "field"}]
      assert sort("field.desc") == [{:desc, "field"}]
      assert sort("field.desc,field2.asc") == [{:desc, "field"}, {:asc, "field2"}]
      assert sort("field.desc,field2.desc") == [{:desc, "field"}, {:desc, "field2"}]
    end
  end
end
