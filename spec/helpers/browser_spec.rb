# frozen_string_literal: true

require 'legion/extensions/identity/helpers/browser'

RSpec.describe Legion::Extensions::Identity::Helpers::Browser do
  subject(:helper) { Object.new.extend(described_class) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('DISPLAY').and_return(nil)
    allow(ENV).to receive(:[]).with('WAYLAND_DISPLAY').and_return(nil)
  end

  it 'does not treat a headless Linux session as interactive' do
    allow(helper).to receive(:browser_host_os).and_return('linux')

    expect(helper.browser_gui_available?).to be(false)
  end

  it 'recognizes a Wayland session without X11' do
    allow(helper).to receive(:browser_host_os).and_return('linux')
    allow(ENV).to receive(:[]).with('WAYLAND_DISPLAY').and_return('wayland-0')

    expect(helper.browser_gui_available?).to be(true)
  end

  it 'recognizes an X11 session without Wayland' do
    allow(helper).to receive(:browser_host_os).and_return('linux')
    allow(ENV).to receive(:[]).with('DISPLAY').and_return(':0')

    expect(helper.browser_gui_available?).to be(true)
  end

  it 'recognizes macOS without X11 environment variables' do
    allow(helper).to receive(:browser_host_os).and_return('darwin')

    expect(helper.browser_gui_available?).to be(true)
  end

  it 'recognizes Windows without X11 environment variables' do
    allow(helper).to receive(:browser_host_os).and_return('mingw')

    expect(helper.browser_gui_available?).to be(true)
  end

  it 'declines unsupported platforms rather than interpreting a URL as a command' do
    allow(helper).to receive(:browser_host_os).and_return('unknown')

    expect(helper.browser_open(url: 'https://example.test/sign-in')).to be(false)
  end
end
