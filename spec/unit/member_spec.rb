require_relative '../../app/api'

module MemberTracker
  RSpec.describe Member do
    describe '.normalize_email' do
      it 'passes through and upcases a normal email' do
        expect(Member.normalize_email('Someone@Example.com')).to eq(['SOMEONE@EXAMPLE.COM', false])
      end

      it 'forces the canonical placeholder when blank' do
        expect(Member.normalize_email('')).to eq([Member::NO_EMAIL_PLACEHOLDER, true])
        expect(Member.normalize_email(nil)).to eq([Member::NO_EMAIL_PLACEHOLDER, true])
      end

      it 'forces the canonical placeholder when bogus is explicitly requested, even with real-looking text present' do
        expect(Member.normalize_email('looks.real@example.com', bogus_requested: true))
          .to eq([Member::NO_EMAIL_PLACEHOLDER, true])
      end

      it 'forces the canonical placeholder when a known historical placeholder is typed without checking bogus' do
        expect(Member.normalize_email('bogus@bogus.com')).to eq([Member::NO_EMAIL_PLACEHOLDER, true])
        expect(Member.normalize_email('BOGUS@NOMAIL.COM')).to eq([Member::NO_EMAIL_PLACEHOLDER, true])
        expect(Member.normalize_email('guest@w7lt.org')).to eq([Member::NO_EMAIL_PLACEHOLDER, true])
      end
    end

    describe '.normalize_callsign' do
      it 'passes through and upcases a normal callsign' do
        expect(Member.normalize_callsign('kd7vdg')).to eq('KD7VDG')
      end

      it 'forces the canonical placeholder when blank' do
        expect(Member.normalize_callsign('')).to eq(Member::NO_CALLSIGN_PLACEHOLDER)
        expect(Member.normalize_callsign(nil)).to eq(Member::NO_CALLSIGN_PLACEHOLDER)
      end

      it 'forces the canonical placeholder when explicitly requested, even with text present' do
        expect(Member.normalize_callsign('KD7VDG', no_callsign_requested: true))
          .to eq(Member::NO_CALLSIGN_PLACEHOLDER)
      end
    end
  end
end
