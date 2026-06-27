defmodule ExGoCD.Materials.MaterialFilterTest do
  use ExUnit.Case, async: true

  alias ExGoCD.Materials.MaterialFilter

  describe "pattern_matches?/2 (GoCD IgnoredFiles parity)" do
    test "*.doc matches root .doc files" do
      assert MaterialFilter.pattern_matches?("*.doc", "a.doc")
      refute MaterialFilter.pattern_matches?("*.doc", "a.pdf")
      refute MaterialFilter.pattern_matches?("*.doc", "subdir/a.doc")
    end

    test "**/*.doc matches .doc at any depth" do
      assert MaterialFilter.pattern_matches?("**/*.doc", "a.doc")
      assert MaterialFilter.pattern_matches?("**/*.doc", "subdir/a.doc")
      assert MaterialFilter.pattern_matches?("**/*.doc", "a/b/c/a.doc")
      refute MaterialFilter.pattern_matches?("**/*.doc", "a.pdf")
    end

    test "Test/**/* ignores everything under Test/" do
      assert MaterialFilter.pattern_matches?("Test/**/*", "Test/foo.txt")
      assert MaterialFilter.pattern_matches?("Test/**/*", "Test/subdir/foo.txt")
      assert MaterialFilter.pattern_matches?("Test/**/*", "Test/subdir/subdir/foo.txt")
      assert MaterialFilter.pattern_matches?("Test/**/*", "Test/subdir/subdir/foo")
      refute MaterialFilter.pattern_matches?("Test/**/*", "Other/foo.txt")
    end

    test "Test/**/*.* matches files with extension under Test/" do
      assert MaterialFilter.pattern_matches?("Test/**/*.*", "Test/foo.txt")
      assert MaterialFilter.pattern_matches?("Test/**/*.*", "Test/subdir/foo.txt")
      refute MaterialFilter.pattern_matches?("Test/**/*.*", "Test/subdir/foo")
    end

    test "*/*.doc matches .doc one level deep only" do
      assert MaterialFilter.pattern_matches?("*/*.doc", "subdir/a.doc")
      refute MaterialFilter.pattern_matches?("*/*.doc", "a.doc")
      refute MaterialFilter.pattern_matches?("*/*.doc", "a/b/c.doc")
    end

    test "**/DocumentFolder/* matches files inside DocumentFolder at any depth" do
      assert MaterialFilter.pattern_matches?("**/DocumentFolder/*", "A/DocumentFolder/d.doc")
      refute MaterialFilter.pattern_matches?("**/DocumentFolder/*", "A/shouldNotBeIgnored.doc")
      refute MaterialFilter.pattern_matches?("**/DocumentFolder/*", "A/DocumentFolder/B/d.doc")
    end

    test "ROOTFOLDER/*.doc matches only in ROOTFOLDER" do
      assert MaterialFilter.pattern_matches?("ROOTFOLDER/*.doc", "ROOTFOLDER/a.doc")
      refute MaterialFilter.pattern_matches?("ROOTFOLDER/*.doc", "shouldNotBeIgnored.doc")

      refute MaterialFilter.pattern_matches?(
               "ROOTFOLDER/*.doc",
               "ANYFOLDER/shouldNotBeIgnored.doc"
             )
    end

    test "case insensitive matching" do
      assert MaterialFilter.pattern_matches?("*.doc", "A.DOC")
      assert MaterialFilter.pattern_matches?("**/TEST/*", "root/test/file.txt")
    end
  end

  describe "all_ignored?/2 (GoCD Modifications.shouldBeIgnoredByFilterIn parity)" do
    test "empty filter returns false (all changes pass)" do
      material = %{filter_ignore: [], filter_include: []}
      mods = [%{path: "src/app.java"}]
      refute MaterialFilter.all_ignored?(material, mods)
    end

    test "nil material returns false" do
      refute MaterialFilter.all_ignored?(nil, [%{path: "file.txt"}])
    end

    test "ignore *.doc — doc-only changes are all ignored" do
      material = %{filter_ignore: ["*.doc"], filter_include: []}
      mods = [%{path: "readme.doc"}, %{path: "guide.doc"}]
      assert MaterialFilter.all_ignored?(material, mods)
    end

    test "ignore *.doc — mixed changes (doc + java) are NOT all ignored" do
      material = %{filter_ignore: ["*.doc"], filter_include: []}
      mods = [%{path: "readme.doc"}, %{path: "src/app.java"}]
      refute MaterialFilter.all_ignored?(material, mods)
    end

    test "ignore **/*.doc — all doc changes ignored" do
      material = %{filter_ignore: ["**/*.doc"], filter_include: []}
      mods = [%{path: "docs/readme.doc"}, %{path: "src/guide.doc"}]
      assert MaterialFilter.all_ignored?(material, mods)
    end

    test "ignore **/*.doc — java file passes through" do
      material = %{filter_ignore: ["**/*.doc"], filter_include: []}
      mods = [%{path: "src/app.java"}]
      refute MaterialFilter.all_ignored?(material, mods)
    end

    test "ignore multiple patterns: *.doc + *.pdf" do
      material = %{filter_ignore: ["*.doc", "*.pdf"], filter_include: []}
      mods = [%{path: "a.doc"}, %{path: "b.pdf"}]
      assert MaterialFilter.all_ignored?(material, mods)
    end

    test "wildcard blacklist **/* ignores everything" do
      material = %{filter_ignore: ["**/*"], filter_include: []}
      mods = [%{path: "a.doc"}, %{path: "a.pdf"}, %{path: "a.java"}]
      assert MaterialFilter.all_ignored?(material, mods)
    end

    test "include-only: only matching paths trigger" do
      material = %{filter_ignore: [], filter_include: ["src/**/*.java"]}
      mods = [%{path: "src/app.java"}]
      refute MaterialFilter.all_ignored?(material, mods)
    end

    test "include-only: non-matching paths are all ignored" do
      material = %{filter_ignore: [], filter_include: ["src/**/*.java"]}
      mods = [%{path: "readme.doc"}, %{path: "test/foo.exs"}]
      assert MaterialFilter.all_ignored?(material, mods)
    end

    test "include-only: mixed changes — one match is enough" do
      material = %{filter_ignore: [], filter_include: ["src/**/*.java"]}
      mods = [%{path: "readme.doc"}, %{path: "src/app.java"}]
      refute MaterialFilter.all_ignored?(material, mods)
    end
  end

  describe "GoCD integration scenarios" do
    test "onlyOnChanges with filter: modified non-ignored file triggers" do
      # Mirrors GoCD's MultipleMaterialsWithFilterTest
      material = %{filter_ignore: ["*.doc", "*.pdf"], filter_include: []}
      mods = [%{path: "src/app.java"}]
      refute MaterialFilter.all_ignored?(material, mods)
    end

    test "onlyOnChanges with filter: only doc changes do not trigger" do
      # Mirrors GoCD's AutoTriggerDependencyResolutionTest
      material = %{filter_ignore: ["*.doc"], filter_include: []}
      mods = [%{path: "readme.doc"}]
      assert MaterialFilter.all_ignored?(material, mods)
    end

    test "multiple materials: one filtered, one not — trigger fires" do
      # Only one material needs passing changes
      mat_ignored = %{filter_ignore: ["*.doc"], filter_include: []}
      mat_passing = %{filter_ignore: [], filter_include: []}

      assert MaterialFilter.all_ignored?(mat_ignored, [%{path: "readme.doc"}])
      refute MaterialFilter.all_ignored?(mat_passing, [%{path: "src/app.java"}])
    end
  end
end
