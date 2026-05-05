require 'rack/test'
require 'json'
require_relative '../../../app/api'

# Routes under /m/ require at least mbr_mgr role (rank 2).
# In dev/test mode api.rb hard-codes session[:auth_user_id] = 22 (auth_u rank 1),
# so all /m/ routes are accessible without additional cookie setup.
module MemberTracker
  RSpec.describe 'Member-Manager Routes (/m)', :db do
    include Rack::Test::Methods

    def app
      MemberTracker::API.new
    end

    # ── Member Query ─────────────────────────────────────────────────────────

    describe 'GET /m/query' do
      it 'renders the member search form' do
        get '/m/query'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/query' do
      it 'returns all members when no filters are applied' do
        post '/m/query', {}
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Members List')
      end

      it 'returns members filtered by type' do
        post '/m/query', 'mbr_full' => 'full'
        expect(last_response.status).to eq(200)
      end

      it 'returns paid-up members when paid_up_q=1' do
        post '/m/query', 'paid_up_q' => '1'
        expect(last_response.status).to eq(200)
      end
    end

    # ── Member CRUD ──────────────────────────────────────────────────────────

    describe 'GET /m/member/create' do
      it 'renders the new-member form' do
        get '/m/member/create'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/member/create' do
      it 'creates a new member and redirects to their show page'
      it 'returns an error when required fields are missing'
      it 'returns an error when a duplicate name is submitted'
    end

    describe 'GET /m/member/edit/:id' do
      it 'renders the member edit form' do
        member = create_member(fname: 'Edit', lname: 'Me')
        get "/m/member/edit/#{member.id}"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Edit')
      end

      it 'returns 500 or redirects for an unknown member id'
    end

    # ── Referral Types ───────────────────────────────────────────────────────

    describe 'GET /m/member/refer/type/list/:id' do
      it 'renders the referral-type member list for all refer types' do
        get '/m/member/refer/type/list/all'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/member/refer/type/create' do
      it 'renders the new referral-type form'
      it 'renders the edit form when an id is supplied'
    end

    describe 'POST /m/member/refer/type/create/:id?' do
      it 'creates a new referral type and redirects'
      it 'updates an existing referral type when id is supplied'
    end

    # ── Auth User Self-Service ────────────────────────────────────────────────

    describe 'GET /m/auth_user/change_password' do
      it 'renders the change-password form' do
        get '/m/auth_user/change_password'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/auth_user/change_password' do
      it 'redirects to /home on a correct current password' do
        # dev session is auth_user id=22; update its password to a known value first
        known_pwd = 'KnownPwd99'
        DB[:auth_users].where(id: 22).update(password: BCrypt::Password.create(known_pwd).to_s)
        post '/m/auth_user/change_password',
             'current_password' => known_pwd,
             'password'         => 'NewPwd1234',
             'confirm_password' => 'NewPwd1234'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/home')
      end

      it 'redirects back with an error on an incorrect current password' do
        post '/m/auth_user/change_password',
             'current_password' => 'WrongPwd99',
             'password'         => 'NewPwd1234',
             'confirm_password' => 'NewPwd1234'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/auth_user/change_password')
      end
    end

    # ── Events ───────────────────────────────────────────────────────────────

    describe 'GET /m/event/create' do
      it 'renders the new-event form' do
        get '/m/event/create'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/event/create' do
      it 'redirects back when the event contact member is missing' do
        post '/m/event/create', 'event_type_id' => '1', 'event_date' => '2024-01-15 10:00',
                                'duration' => 'none'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/event/create')
      end

      it 'redirects back when the event type is set to none' do
        post '/m/event/create', 'mbr_id' => '22', 'event_type_id' => 'none',
                                'event_date' => '2024-01-15 10:00', 'duration' => 'none'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/event/create')
      end

      it 'redirects back when the event date is incorrectly formatted' do
        post '/m/event/create', 'mbr_id' => '22', 'event_type_id' => '1',
                                'event_date' => 'not-a-date', 'duration' => 'none'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/event/create')
      end

      it 'creates a new event and redirects'
    end

    describe 'GET /m/event/edit/:id' do
      it 'renders the event edit form for a valid event'
      it 'returns 500 or redirects for an unknown event id'
    end

    describe 'GET /m/event/list/:id' do
      it 'renders the event list for all events' do
        get '/m/event/list/all'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/event/attendees/show/:id' do
      it 'renders the attendee list for a valid event'
    end

    describe 'GET /m/event/type/create' do
      it 'renders the event-type form' do
        get '/m/event/type/create/'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/event/type/create/:id?' do
      it 'creates a new event type and redirects' do
        post '/m/event/type/create/', 'event_type_name' => 'TestType',
                                      'event_type_descr' => 'A test event type'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/event/type/create')
      end

      it 'updates an existing event type when id is supplied'
    end

    # ── Logs ─────────────────────────────────────────────────────────────────

    describe 'GET /m/log/create' do
      # The route is /m/log/create/:id? — the trailing slash is required when :id is omitted.
      it 'renders the general log form with no member pre-selected' do
        get '/m/log/create/'
        expect(last_response.status).to eq(200)
      end

      it 'renders the member-note form pre-selected for a valid member id' do
        member = create_member
        get "/m/log/create/#{member.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/log/create' do
      it 'saves a general log entry and redirects to the log view' do
        post '/m/log/create', 'notes' => 'A general log entry'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/log/view/auth_user')
      end

      it 'saves a member note and redirects to the member show page'
    end

    describe 'GET /m/log/view/:type' do
      it 'renders the log list for the current auth_user' do
        get '/m/log/view/auth_user'
        expect(last_response.status).to eq(200)
      end

      it 'renders the log list for all auth_users' do
        get '/m/log/view/all'
        expect(last_response.status).to eq(200)
      end

      it 'redirects to /home when no general logs exist' do
        get '/m/log/view/general'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/home')
      end
    end

    # ── Units ─────────────────────────────────────────────────────────────────

    describe 'GET /m/unit/list/:unit_type' do
      it 'renders an empty unit list for all types' do
        get '/m/unit/list/all'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/unit/create' do
      it 'renders the new-unit form' do
        get '/m/unit/create'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/unit/create' do
      it 'creates a unit and redirects'
      it 'returns an error when required unit fields are missing'
    end

    describe 'GET /m/unit/edit/:id' do
      it 'renders the unit edit form for a valid unit'
    end

    describe 'POST /m/unit/update' do
      it 'updates a unit record and redirects'
    end

    describe 'GET /m/unit/type/create' do
      it 'renders the unit-type form'
    end

    describe 'POST /m/unit/type/create/:id?' do
      it 'creates a new unit type and redirects'
      it 'updates an existing unit type when id is supplied'
    end

    describe 'GET /m/unit/display/fam_unit/status' do
      it 'renders the family-unit status dashboard with no family units' do
        get '/m/unit/display/fam_unit/status'
        expect(last_response.status).to eq(200)
      end
    end

    # ── Payments ──────────────────────────────────────────────────────────────

    describe 'GET /m/payment/new/:id' do
      it 'renders the new-payment form for a valid member'
      it 'returns 500 or redirects for an unknown member id'
    end

    describe 'POST /m/payment/new' do
      it 'records a payment and redirects to the member page'
      it 'returns an error for an invalid payment amount'
    end

    describe 'GET /m/payments/edit/:id' do
      it 'renders the payment edit form for a valid payment id'
    end

    describe 'POST /m/payments/edit' do
      it 'updates the payment record and redirects'
    end

    describe 'GET /m/payment/show/:id' do
      it 'renders the payment detail for a valid payment id'
    end

    describe 'GET /m/payments/show' do
      it 'renders an empty payment list when no payments exist' do
        get '/m/payments/show'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/payments/destroy/:id' do
      it 'renders the destroy-confirmation page for a valid payment id'
    end

    describe 'POST /m/payments/destroy' do
      it 'deletes the payment and redirects'
      it 'redirects without deleting when confirmation is not "Yes"' do
        post '/m/payments/destroy', 'pay_id' => '0', 'confirm' => 'no'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/payments/show')
      end
    end

    describe 'GET /m/payments/report/:type' do
      it 'renders a payment summary report for a given type'
      it 'returns a CSV export for format=csv'
    end

    # ── Renewals ──────────────────────────────────────────────────────────────

    describe 'GET /m/mbr_renewals/show' do
      it 'renders the renewals dashboard with no active renewals' do
        get '/m/mbr_renewals/show'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/mbr_renewals/new/:id' do
      # Template calls mbrship_renewal_date.strftime — member must have a date set.
      it 'renders the new-renewal form for a valid member' do
        member = create_member(mbrship_renewal_date: Date.today)
        get "/m/mbr_renewals/new/#{member.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/mbr_renewals/new' do
      it 'redirects with an error when the date is unparseable' do
        post '/m/mbr_renewals/new', 'mbrship_renewal_date' => 'not-a-date'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/mbr_renewals/show')
      end

      it 'redirects with an error when the renewal year is out of range' do
        post '/m/mbr_renewals/new', 'mbrship_renewal_date' => '01/01/99'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/mbr_renewals/show')
      end

      it 'creates a renewal record and redirects to the member page'
    end

    describe 'GET /m/mbr_renewals/edit/:id' do
      it 'renders the renewal edit form for a valid renewal id'
    end

    describe 'POST /m/mbr_renewals/edit' do
      it 'updates the renewal record and redirects'
    end

    describe 'GET /m/mbr_renewals/destroy/:id' do
      it 'renders the destroy-confirmation page for a valid renewal id'
    end

    describe 'POST /m/mbr_renewals/destroy' do
      it 'deletes the renewal and redirects'
    end

    # ── Non-Renewals ──────────────────────────────────────────────────────────

    describe 'GET /m/mbr_non_renewals/edit/:id' do
      it 'renders the non-renewal edit form for a valid record'
    end

    describe 'POST /m/mbr_non_renewals/update/:id' do
      it 'updates the non-renewal record and redirects'
    end

    describe 'GET /m/mbr_non_renewals/destroy/:id' do
      it 'renders the destroy-confirmation page for a valid non-renewal id'
    end

    describe 'POST /m/mbr_non_renewals/destroy/:id' do
      it 'deletes the non-renewal record and redirects'
    end

    # ── Followup ──────────────────────────────────────────────────────────────

    describe 'GET /m/followup/show' do
      it 'renders the followup dashboard' do
        get '/m/followup/show'
        expect(last_response.status).to eq(200)
      end
    end

    # ── Member Actions ────────────────────────────────────────────────────────

    describe 'GET /m/member_action/add_note' do
      it 'redirects to followup when no member action id is provided' do
        get '/m/member_action/add_note'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'redirects to followup when no action type is provided' do
        get '/m/member_action/add_note', 'mbr_action_id' => '1'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'redirects to followup when an invalid action type is provided' do
        get '/m/member_action/add_note', 'mbr_action_id' => '1', 'type' => 'bad_type'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'renders the add-note form for a valid member action'
    end

    describe 'POST /m/member_action/add_note' do
      it 'redirects to followup when no member action id is provided' do
        post '/m/member_action/add_note', {}
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'redirects to followup when the note body is blank' do
        post '/m/member_action/add_note', 'mbr_action_id' => '1', 'note' => ''
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'saves the note and redirects to the followup page'
    end

    # ── Call-Me Requests ──────────────────────────────────────────────────────

    describe 'GET /m/mbr_callme/new/:id' do
      it 'renders the new call-me form for a valid member' do
        member = create_member(fname: 'CallMe', lname: 'Test')
        get "/m/mbr_callme/new/#{member.id}"
        expect(last_response.status).to eq(200)
      end

      it 'redirects to followup for an unknown member id' do
        get '/m/mbr_callme/new/0'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end
    end

    describe 'POST /m/mbr_callme/new' do
      it 'redirects to followup when no target member is provided' do
        post '/m/mbr_callme/new', {}
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'redirects to followup when no note is provided' do
        post '/m/mbr_callme/new', 'target_mbr_id' => '1', 'note' => ''
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'creates the call-me record and redirects to the followup page'
    end

    describe 'GET /m/mbr_callme/edit/:id' do
      it 'renders the call-me edit form for a valid record'
    end

    describe 'POST /m/mbr_callme/update/:id' do
      it 'updates the call-me record and redirects'
    end
  end
end
