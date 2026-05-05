require_relative '../../../app/services/jotform_parser'

module MemberTracker
  RSpec.describe JotformParser do
    # Realistic log note fixture: two topics (one on the question line, one as a
    # continuation), one frequency, one mode, and a callback preference.
    SURVEY_NOTE = <<~NOTE
      New dues payment via jotform renewal form
      What topics would you like at meetings? Contesting
      Portable Operating, SOTA POTA
      What frequencies do you operate? VHF/UHF
      What modes do you use? CW
      Would you like a callback? No, I do not want a callback
      **end of form
    NOTE

    # ── JotformParser.categorize ──────────────────────────────────────────────

    describe '.categorize' do
      context 'topic questions' do
        it 'returns T1 for Portable Operating' do
          expect(described_class.categorize('Portable Operating, SOTA POTA', :topic)).to eq('T1')
        end

        it 'returns T2 for Contesting' do
          expect(described_class.categorize('Contesting', :topic)).to eq('T2')
        end

        it 'returns T8 for Digital Modes' do
          expect(described_class.categorize('Digital Modes: FT8 etc', :topic)).to eq('T8')
        end

        it 'returns T10 for Emergency Preparedness' do
          expect(described_class.categorize('Emergency preparedness and ARES', :topic)).to eq('T10')
        end

        it 'returns T11|<text> for an unrecognized topic' do
          expect(described_class.categorize('Build your own SDR', :topic)).to eq('T11|Build your own SDR')
        end
      end

      context 'frequency questions' do
        it 'returns F1 for High Frequency HF' do
          expect(described_class.categorize('High Frequency HF', :freq)).to eq('F1')
        end

        it 'returns F2 for VHF/UHF' do
          expect(described_class.categorize('VHF/UHF', :freq)).to eq('F2')
        end

        it 'returns F3 for Microwave' do
          expect(described_class.categorize('Microwave', :freq)).to eq('F3')
        end

        it 'returns F4 for Low Frequency' do
          expect(described_class.categorize('Low Frequency (LF)', :freq)).to eq('F4')
        end

        it 'returns F5 for None/not applicable' do
          expect(described_class.categorize('None, new at this', :freq)).to eq('F5')
        end
      end

      context 'mode questions' do
        it 'returns M1 for Voice Phone' do
          expect(described_class.categorize('Voice Phone (SSB, FM, etc)', :mode)).to eq('M1')
        end

        it 'returns M2 for CW' do
          expect(described_class.categorize('CW', :mode)).to eq('M2')
        end

        it 'returns M3 for Digital' do
          expect(described_class.categorize('Digital (FT8, RTTY, etc)', :mode)).to eq('M3')
        end

        it 'returns M4 for None' do
          expect(described_class.categorize('None, new at this', :mode)).to eq('M4')
        end

        it 'returns F5|<text> for an unrecognized mode' do
          expect(described_class.categorize('Smoke Signals', :mode)).to eq('F5|Smoke Signals')
        end
      end
    end

    # ── JotformParser.parse_note ──────────────────────────────────────────────

    describe '.parse_note' do
      it 'returns nil for a note with no jotform marker' do
        expect(described_class.parse_note('just a regular payment note')).to be_nil
      end

      it 'returns nil when jotform marker is present but no questions were captured' do
        expect(described_class.parse_note("payment via jotform\n**end")).to be_nil
      end

      it 'returns [codes, other] for a well-formed survey note' do
        codes, other = described_class.parse_note(SURVEY_NOTE)
        expect(codes).to contain_exactly('T2', 'T1', 'F2', 'M2', 'CB2')
        expect(other[:topics]).to be_empty
        expect(other[:modes]).to be_empty
      end

      it 'captures continuation lines as additional answers for the current question' do
        codes, _ = described_class.parse_note(SURVEY_NOTE)
        # "Portable Operating, SOTA POTA" is a continuation line that produces T1
        expect(codes).to include('T1', 'T2')
      end

      it 'adds T11 to codes and captures other-topic text in other[:topics]' do
        note = "jotform\nWhat topics? Build your own SDR\n**end"
        codes, other = described_class.parse_note(note)
        expect(codes).to include('T11')
        expect(other[:topics]).to include('Build your own SDR')
      end

      it 'adds F5 to codes and captures other-mode text in other[:modes]' do
        note = "jotform\nWhat modes? Smoke Signals\n**end"
        codes, other = described_class.parse_note(note)
        expect(codes).to include('F5')
        expect(other[:modes]).to include('Smoke Signals')
      end

      it 'returns CB1 for a yes-callback response' do
        note = "jotform\nWould you like a callback? Yes, I would like a callback\n**end"
        codes, _ = described_class.parse_note(note)
        expect(codes).to include('CB1')
      end

      it 'stops capturing at a line starting with **' do
        note = "jotform\nWhat topics? Contesting\n**separator\nWhat freq? VHF/UHF\n**end"
        codes, _ = described_class.parse_note(note)
        # The freq question appears after the ** break and must not be captured
        expect(codes).not_to include('F2')
        expect(codes).to include('T2')
      end
    end
  end
end
