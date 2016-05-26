require 'rubygems'

initialized = false
test_ui = nil
generator = nil
tmp_dir = nil
oldwd = nil

describe Fastlane::PluginGenerator do
  describe '#generate' do
    let(:plugin_info) { Fastlane::PluginInfo.new('tester', 'Fabricio Devtoolio', 'fabric.devtools@gmail.com', 'summary', 'description') }
    let(:plugin_name) { plugin_info.plugin_name }
    let(:gem_name) { plugin_info.gem_name }
    let(:require_path) { plugin_info.require_path }
    let(:author) { plugin_info.author }
    let(:email) { plugin_info.email }
    let(:summary) { plugin_info.summary }
    let(:description) { plugin_info.description }

    before(:each) do
      unless initialized
        test_ui = Fastlane::PluginGeneratorUI.new
        allow(test_ui).to receive(:message)
        allow(test_ui).to receive(:success)
        allow(test_ui).to receive(:input).and_raise(":input call was not mocked!")
        allow(test_ui).to receive(:confirm).and_raise(":confirm call was not mocked!")

        generator = Fastlane::PluginGenerator.new(test_ui)

        tmp_dir = Dir.mktmpdir
        oldwd = Dir.pwd
        Dir.chdir(tmp_dir)

        expect(test_ui).to receive(:input).and_return(plugin_name)
        expect(test_ui).to receive(:input).and_return(author)
        expect(test_ui).to receive(:input).and_return(email)
        expect(test_ui).to receive(:input).and_return(summary)
        expect(test_ui).to receive(:input).and_return(description)

        generator.generate

        initialized = true
      end
    end

    after(:all) do
      Dir.chdir(oldwd) if oldwd
      FileUtils.remove_entry(tmp_dir) if tmp_dir

      test_ui = nil
      generator = nil
      tmp_dir = nil
      oldwd = nil
      initialized = false
    end

    it "creates gem root directory" do
      expect(File.directory?(File.join(tmp_dir, gem_name))).to be(true)
    end

    it "creates a .rspec file" do
      dot_rspec_file = File.join(tmp_dir, gem_name, '.rspec')
      expect(File.exist?(dot_rspec_file)).to be(true)

      dot_rspec_lines = File.read(dot_rspec_file).lines

      [
        "--require spec_helper\n",
        "--color\n",
        "--format d\n"
      ].each do |option|
        expect(dot_rspec_lines).to include(option)
      end
    end

    it "creates a .gitignore file" do
      dot_gitignore_file = File.join(tmp_dir, gem_name, '.gitignore')
      expect(File.exist?(dot_gitignore_file)).to be(true)

      dot_gitignore_lines = File.read(dot_gitignore_file).lines

      [
        "*.gem\n",
        "Gemfile.lock\n",
        "/.yardoc/\n",
        "/_yardoc/\n",
        "/doc/\n",
        "/rdoc/\n"
      ].each do |item|
        expect(dot_gitignore_lines).to include(item)
      end
    end

    it "creates a Gemfile" do
      gemfile = File.join(tmp_dir, gem_name, 'Gemfile')
      expect(File.exist?(gemfile)).to be(true)

      gemfile_lines = File.read(gemfile).lines

      [
        "source 'https://rubygems.org'\n",
        "gemspec\n"
      ].each do |line|
        expect(gemfile_lines).to include(line)
      end
    end

    it "creates a plugin.rb file for the plugin" do
      plugin_rb_file = File.join(tmp_dir, gem_name, 'lib', 'fastlane', 'plugin', "#{plugin_name}.rb")
      expect(File.exist?(plugin_rb_file)).to be(true)

      plugin_rb_contents = File.read(plugin_rb_file)

      Dir.chdir(gem_name) do
        # Ensure that the require statements inside the plugin.rb contents will resolve correctly
        lib = File.expand_path('lib')
        $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

        # rubocop:disable Lint/Eval
        eval(plugin_rb_contents)
        # rubocop:enable Lint/Eval

        # If we evaluate the contents of the generated plugin.rb file,
        # we'll get the all_classes helper method defined. This ensures
        # that the syntax is valid, and lets us interrogate the class for
        # the behavior!
        action_class = Object.const_get("Fastlane::#{plugin_name.capitalize}")

        all_classes = action_class.all_classes
        expect(all_classes).to contain_exactly(
          File.expand_path("lib/#{plugin_info.actions_path}/#{plugin_name}_action.rb"),
          File.expand_path("lib/#{plugin_info.helper_path}/#{plugin_name}_helper.rb")
        )

        # Get the relative paths to require, check that they have already been required.
        require_paths = all_classes.map { |c| c.gsub(lib + '/', '').gsub('.rb', '') }
        require_paths.each { |path| expect(require(path)).to be(false) }
      end
    end

    it "creates a README that contains the gem name" do
      readme_file = File.join(tmp_dir, gem_name, 'README.md')
      expect(File.exist?(readme_file)).to be(true)

      readme_contents = File.read(readme_file)

      expect(readme_contents).to include(gem_name)
      expect(readme_contents.length).to be > 100
    end

    it "creates a module for the VERSION" do
      # We'll be asserting that this file is valid Ruby when we check
      # the value of the version as evaluated by the gemspec!
      expect(File.exist?(File.join(tmp_dir, gem_name, 'lib', require_path, 'version.rb'))).to be(true)
    end

    it "creates a LICENSE" do
      readme_file = File.join(tmp_dir, gem_name, 'LICENSE')
      expect(File.exist?(readme_file)).to be(true)

      readme_contents = File.read(readme_file)

      expect(readme_contents).to include(author)
      expect(readme_contents).to include(email)
      expect(readme_contents.length).to be > 100
    end

    it "creates a Action class" do
      action_file = File.join(tmp_dir, gem_name, 'lib', plugin_info.actions_path, "#{plugin_name}_action.rb")
      expect(File.exist?(action_file)).to be(true)

      action_contents = File.read(action_file)

      # rubocop:disable Lint/Eval
      eval(action_contents)
      # rubocop:enable Lint/Eval

      # If we evaluate the contents of the generated action file,
      # we'll get the Action class defined. This ensures that the
      # syntax is valid, and lets us interrogate the class for its
      # behavior!
      action_class = Object.const_get("Fastlane::Actions::#{plugin_name.capitalize}Action")

      # Check that the default `run` method behavior calls UI.message
      expect(UI).to receive(:message).with(/#{plugin_name}/)
      action_class.run(nil)

      # Check the default behavior of the rest of the methods
      expect(action_class.description).to eq(description)
      expect(action_class.authors).to eq([author])
      expect(action_class.available_options).to eq([])
      expect(action_class.is_supported?(:ios)).to be(true)
    end

    it "creates a complete, valid gemspec" do
      gemspec_file = File.join(tmp_dir, gem_name, "#{gem_name}.gemspec")
      expect(File.exist?(gemspec_file)).to be(true)

      # Because the gemspec expects to be evaluated from the same directory
      # it lives in, we need to jump in there while we examine it.
      Dir.chdir(gem_name) do
        # If we evaluate the contents of the generated gemspec file,
        # we'll get the Gem Specification object back out, which
        # ensures that the syntax is valid, and lets us interrogate
        # the values!
        #
        # rubocop:disable Lint/Eval
        gemspec = eval(File.read(gemspec_file))
        # rubocop:enable Lint/Eval

        expect(gemspec.name).to eq(gem_name)
        expect(gemspec.author).to eq(author)
        expect(gemspec.version).to eq(Gem::Version.new('0.1.0'))
        expect(gemspec.email).to eq(email)
        expect(gemspec.summary).to eq(summary)
        expect(gemspec.description).to eq(description)
        expect(gemspec.development_dependencies).to contain_exactly(
          Gem::Dependency.new("pry", Gem::Requirement.new([">= 0"]), :development),
          Gem::Dependency.new("bundler", Gem::Requirement.new([">= 0"]), :development),
          Gem::Dependency.new("rspec", Gem::Requirement.new([">= 0"]), :development),
          Gem::Dependency.new("fastlane", Gem::Requirement.new([">= #{Fastlane::VERSION}"]), :development)
        )
      end
    end

    it "creates a valid helper class" do
      helper_file = File.join(tmp_dir, gem_name, 'lib', plugin_info.helper_path, "#{plugin_info.plugin_name}_helper.rb")
      expect(File.exist?(helper_file)).to be(true)

      helper_contents = File.read(helper_file)

      # rubocop:disable Lint/Eval
      eval(helper_contents)
      # rubocop:enable Lint/Eval

      # If we evaluate the contents of the generated helper file,
      # we'll get the helper class defined. This ensures that the
      # syntax is valid, and lets us interrogate the class for its
      # behavior!
      helper_class = Object.const_get("Fastlane::Helper::#{plugin_name.capitalize}Helper")

      # Check that the class was successfully defined
      expect(UI).to receive(:message).with(/#{plugin_name}/)
      helper_class.show_message
    end

    it "creates a spec_helper.rb file" do
      spec_helper_file = File.join(tmp_dir, gem_name, 'spec', 'spec_helper.rb')
      expect(File.exist?(spec_helper_file)).to be(true)

      spec_helper_module = Object.const_get("SpecHelper")
      expect(spec_helper_module).not_to be(nil)
    end

    it "creates a action_spec.rb file" do
      action_spec_file = File.join(tmp_dir, gem_name, 'spec', 'action_spec.rb')
      expect(File.exist?(action_spec_file)).to be(true)

      # Actually run our generated spec as part of this spec #yodawg
      Dir.chdir(gem_name) do
        `rspec &> /dev/null`
        expect($?.exitstatus).to be(0)
      end
    end
  end
end
