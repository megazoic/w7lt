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
      # Minimal params mirroring what the new-member form submits.
      let(:new_member_params) do
        {
          'id' => '', 'fname' => 'John', 'lname' => 'Newtester',
          'callsign' => 'W9NEW', 'email' => '', 'callme' => '',
          'callwhy' => '', 'email_bogus' => 'false', 'ok_to_email' => '0',
          'street' => '', 'city' => '', 'state' => '', 'zip' => '',
          'phh' => '', 'phh_pub' => '0', 'phw' => '', 'phw_pub' => '0',
          'phm' => '', 'phm_pub' => '0', 'license_class' => 'tech',
          'mbr_since' => '2024-01', 'notes' => '', 'refer_type_id' => 'none',
          'mbrship_renewal_date' => '', 'arrl' => '0', 'ares' => '0',
          'net' => '0', 've' => '0', 'elmer' => '0', 'sota' => '0',
          'payment' => '', 'mode_phone' => '0', 'mode_cw' => '0'
        }
      end

      it 'creates a new member and redirects to their show page' do
        post '/m/member/create', new_member_params
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/r/member/show/')
      end

      # Required-field validation is client-side only (HTML5 + script.js);
      # the server passes params directly to the model without explicit checks.

      it 'returns an error when a duplicate name is submitted' do
        create_member(fname: 'JOHN', lname: 'NEWTESTER')
        post '/m/member/create', new_member_params
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('already been entered')
      end
    end

    describe 'GET /m/member/edit/:id' do
      it 'renders the member edit form' do
        member = create_member(fname: 'Edit', lname: 'Me')
        get "/m/member/edit/#{member.id}"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('Edit')
      end

      it 'redirects for an unknown member id' do
        get '/m/member/edit/999999'
        expect(last_response.status).to eq(302)
      end
    end

    # ── Referral Types ───────────────────────────────────────────────────────

    describe 'GET /m/member/refer/type/list/:id' do
      it 'renders the referral-type member list for all refer types' do
        get '/m/member/refer/type/list/all'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/member/refer/type/create' do
      it 'renders the new referral-type form' do
        get '/m/member/refer/type/create'
        expect(last_response.status).to eq(200)
      end

      it 'renders the edit form when an id is supplied' do
        rt_id = DB[:refer_types].insert(name: 'TestRef', descr: 'Test referral')
        get "/m/member/refer/type/create/#{rt_id}"
        expect(last_response.status).to eq(200)
        expect(last_response.body).to include('TestRef')
      end
    end

    describe 'POST /m/member/refer/type/create/:id?' do
      it 'creates a new referral type and redirects' do
        post '/m/member/refer/type/create/', 'refer_type_name' => 'NewRef',
                                             'refer_type_descr' => 'New referral type',
                                             'refer_type_notes' => 'Notes for this action'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/member/refer/type/list/all')
      end

      it 'updates an existing referral type when id is supplied' do
        rt_id = DB[:refer_types].insert(name: 'OldRef', descr: 'Old desc')
        post "/m/member/refer/type/create/#{rt_id}", 'refer_type_name' => 'UpdatedRef',
                                                      'refer_type_descr' => 'Updated desc',
                                                      'old_type_name' => 'OldRef',
                                                      'old_type_descr' => 'Old desc',
                                                      'refer_type_notes' => 'Notes for this action'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include("/m/member/refer/type/list/#{rt_id}")
      end
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

      it 'creates a new event and redirects' do
        event_type = create_event_type
        post '/m/event/create', {
          'mbr_id'        => '22',
          'event_type_id' => event_type.id.to_s,
          'event_date'    => '2026-01-15 10:00',
          'duration'      => 'none',
          'name'          => 'Test Event',
          'descr'         => 'A test event',
          'general_notes' => 'test notes'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/event/list/')
      end
    end

    describe 'GET /m/event/edit/:id' do
      it 'renders the event edit form for a valid event' do
        member     = create_member
        event_type = create_event_type
        event      = create_event(member: member, event_type: event_type)
        event_action_id = DB[:actions].where(type: 'event').get(:id)
        create_log(mbr_id: member.id, event_id: event.id, action_id: event_action_id, notes: 'event log')
        get "/m/event/edit/#{event.id}"
        expect(last_response.status).to eq(200)
      end

      it 'redirects for an unknown event id' do
        get '/m/event/edit/999999'
        expect(last_response.status).to eq(302)
      end
    end

    describe 'GET /m/event/list/:id' do
      it 'renders the event list for all events' do
        get '/m/event/list/all'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/event/attendees/show/:id' do
      it 'renders the attendee list for a valid event' do
        member     = create_member
        event_type = create_event_type
        event      = create_event(member: member, event_type: event_type)
        get "/m/event/attendees/show/#{event.id}"
        expect(last_response.status).to eq(200)
      end
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

      it 'updates an existing event type when id is supplied' do
        event_type = create_event_type
        post "/m/event/type/create/#{event_type.id}", {
          'event_type_name'  => 'UpdatedType',
          'event_type_descr' => 'Updated description'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/event/type/create')
      end
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

      it 'saves a member note and redirects to the member show page' do
        member    = create_member
        action_id = DB[:actions].where(type: 'member_general_note').get(:id)
        post '/m/log/create', {
          'mbr_id'     => member.id.to_s,
          'notes'      => 'A member note',
          'log_action' => action_id.to_s
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include("/r/member/show/#{member.id}")
      end
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
      it 'creates a unit and redirects' do
        unit_type = create_unit_type(type: 'elmer')
        member    = create_member
        post '/m/unit/create', {
          'unit_type_id' => unit_type.id.to_s,
          'unit_name'    => 'Test Unit',
          'unit_notes'   => '',
          "id:#{member.id}" => '1'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/unit/list/')
      end

      # No server-side validation for missing fields — unit_type and members are enforced
      # client-side only (script.js + HTML5 required attributes).
    end

    describe 'GET /m/unit/edit/:id' do
      it 'renders the unit edit form for a valid unit' do
        unit_type = create_unit_type
        unit      = create_unit(unit_type: unit_type)
        get "/m/unit/edit/#{unit.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/unit/update' do
      it 'updates a unit record and redirects' do
        unit_type = create_unit_type
        unit      = create_unit(unit_type: unit_type, name: 'Old Name')
        post '/m/unit/update', {
          'unit_id' => unit.id.to_s,
          'name'    => 'New Name',
          'active'  => '1',
          'notes'   => 'updating name'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/unit/list/')
      end
    end

    describe 'GET /m/unit/type/create' do
      it 'renders the unit-type form' do
        get '/m/unit/type/create/'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/unit/type/create/:id?' do
      it 'creates a new unit type and redirects' do
        post '/m/unit/type/create/', {
          'unit_type_name'  => 'NewUnitType',
          'unit_type_descr' => 'A new unit type'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/unit/type/create')
      end

      it 'updates an existing unit type when id is supplied' do
        unit_type = create_unit_type
        post "/m/unit/type/create/#{unit_type.id}", {
          'unit_type_name'  => 'UpdatedType',
          'unit_type_descr' => 'Updated description'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/unit/type/create')
      end
    end

    describe 'GET /m/unit/display/fam_unit/status' do
      it 'renders the family-unit status dashboard with no family units' do
        get '/m/unit/display/fam_unit/status'
        expect(last_response.status).to eq(200)
      end
    end

    # ── Payments ──────────────────────────────────────────────────────────────

    describe 'GET /m/payment/new/:id' do
      it 'renders the new-payment form for a valid member' do
        member = create_member(mbr_type: 'full')
        get "/m/payment/new/#{member.id}"
        expect(last_response.status).to eq(200)
      end

      it 'redirects for an unknown member id' do
        get '/m/payment/new/999999'
        expect(last_response.status).to eq(302)
      end
    end

    describe 'POST /m/payment/new' do
      let(:donation_type_id) { DB[:payment_types].where(type: 'Donation Other').get(:id) }
      let(:cash_method_id)   { DB[:payment_methods].where(mode: 'Cash').get(:id) }

      it 'records a donation payment and redirects to the payments page' do
        member = create_member
        post '/m/payment/new', {
          'mbr_id'         => member.id.to_s,
          'payment_type'   => donation_type_id.to_s,
          'payment_method' => cash_method_id.to_s,
          'nonDues_pmt'    => '10',
          'notes'          => ''
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/payments/show')
      end

      # No server-side amount validation — empty amount fails DB constraint; error is
      # caught and redirects to /m/payments/show with session[:msg] set.
      it 'returns an error for an invalid payment amount' do
        member = create_member
        post '/m/payment/new', {
          'mbr_id'         => member.id.to_s,
          'payment_type'   => donation_type_id.to_s,
          'payment_method' => cash_method_id.to_s,
          'nonDues_pmt'    => '',
          'notes'          => ''
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/payments/show')
      end
    end

    describe 'GET /m/payments/edit/:id' do
      it 'renders the payment edit form for a valid payment id' do
        member = create_member
        payment = create_payment(member: member)
        get "/m/payments/edit/#{payment.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/payments/edit' do
      it 'updates the payment record and redirects' do
        member  = create_member
        payment = create_payment(member: member)
        post '/m/payments/edit', {
          'pay_id'         => payment.id.to_s,
          'pay_log_id'     => payment.log_id.to_s,
          'payment_type'   => payment.payment_type_id.to_s,
          'payment_method' => payment.payment_method_id.to_s,
          'payment_amt'    => '15.0',
          'notes'          => 'updated notes'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/payments/show')
      end
    end

    describe 'GET /m/payment/show/:id' do
      it 'renders the payment detail for a valid payment id' do
        member  = create_member
        payment = create_payment(member: member)
        get "/m/payment/show/#{payment.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/payments/show' do
      it 'renders an empty payment list when no payments exist' do
        get '/m/payments/show'
        expect(last_response.status).to eq(200)
      end
    end

    describe 'GET /m/payments/destroy/:id' do
      it 'renders the destroy-confirmation page for a valid payment id' do
        member  = create_member
        payment = create_payment(member: member)
        get "/m/payments/destroy/#{payment.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/payments/destroy' do
      it 'deletes the payment and redirects' do
        member  = create_member
        payment = create_payment(member: member)
        post '/m/payments/destroy', {
          'pay_id'  => payment.id.to_s,
          'confirm' => 'Yes',
          'notes'   => ''
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/payments/show')
      end

      it 'redirects without deleting when confirmation is not "Yes"' do
        post '/m/payments/destroy', 'pay_id' => '0', 'confirm' => 'no'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/payments/show')
      end
    end

    describe 'GET /m/payments/report/:type/:format?' do
      it 'renders an HTML payment summary report' do
        get '/m/payments/report/all/html'
        expect(last_response.status).to eq(200)
      end

      it 'returns a CSV export' do
        get '/m/payments/report/all/csv'
        expect(last_response.status).to eq(200)
      end
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

      it 'creates a renewal record and redirects to /m/mbr_renewals/show' do
        member = create_member(mbrship_renewal_date: Date.today)
        event_type_id = DB[:renewal_event_types].where(name: 'reminder sent').get(:id)
        post '/m/mbr_renewals/new', {
          'mbr_id'                   => member.id.to_s,
          'mbrship_renewal_date'     => Date.today.strftime('%D'),
          'mbrship_renewal_halt'     => 'false',
          'mbrship_renewal_active'   => 'false',
          'mbrship_renewal_contacts' => '0',
          'event_type'               => event_type_id.to_s,
          'notes'                    => 'test renewal note'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/mbr_renewals/show')
      end
    end

    describe 'GET /m/mbr_renewals/edit/:id' do
      it 'renders the renewal edit form for a valid renewal id' do
        member  = create_member(mbrship_renewal_date: Date.today)
        renewal = create_mbr_renewal(member: member)
        get "/m/mbr_renewals/edit/#{renewal.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/mbr_renewals/edit' do
      it 'updates the renewal record and redirects' do
        member  = create_member(mbrship_renewal_date: Date.today)
        renewal = create_mbr_renewal(member: member)
        event_type_id = DB[:renewal_event_types].where(name: 'reminder sent').get(:id)
        post '/m/mbr_renewals/edit', {
          'rnwal_id'                 => renewal.id.to_s,
          'mbrship_renewal_date'     => Date.today.strftime('%D'),
          'mbrship_renewal_halt'     => 'false',
          'mbrship_renewal_active'   => 'false',
          'mbrship_renewal_contacts' => '1',
          'event_type'               => event_type_id.to_s,
          'notes'                    => 'updated notes'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/mbr_renewals/show')
      end
    end

    describe 'GET /m/mbr_renewals/destroy/:id' do
      it 'renders the destroy-confirmation page for a valid renewal id' do
        member  = create_member(mbrship_renewal_date: Date.today)
        renewal = create_mbr_renewal(member: member)
        get "/m/mbr_renewals/destroy/#{renewal.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/mbr_renewals/destroy' do
      it 'deletes the renewal and redirects' do
        member  = create_member(mbrship_renewal_date: Date.today)
        renewal = create_mbr_renewal(member: member)
        post '/m/mbr_renewals/destroy', {
          'rnwl_id' => renewal.id.to_s,
          'confirm' => 'Yes',
          'notes'   => ''
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/mbr_renewals/show')
      end
    end

    # ── Non-Renewals ──────────────────────────────────────────────────────────

    describe 'GET /m/mbr_non_renewals/edit/:id' do
      it 'renders the non-renewal edit form for a valid record' do
        member = create_member
        action = create_member_action(member: member)
        get "/m/mbr_non_renewals/edit/#{action.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/mbr_non_renewals/update/:id' do
      it 'updates the non-renewal record and redirects' do
        member = create_member
        action = create_member_action(member: member)
        post "/m/mbr_non_renewals/update/#{action.id}", {
          'id'                => action.id.to_s,
          'tasked_to_mbr_id'  => '',
          'completed'         => '',
          'notes'             => 'updated followup note'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end
    end

    describe 'GET /m/mbr_non_renewals/destroy/:id' do
      it 'renders the destroy-confirmation page for a valid non-renewal id' do
        member = create_member
        action = create_member_action(member: member)
        get "/m/mbr_non_renewals/destroy/#{action.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/mbr_non_renewals/destroy/:id' do
      it 'deletes the non-renewal record and redirects' do
        member = create_member
        action = create_member_action(member: member)
        post "/m/mbr_non_renewals/destroy/#{action.id}", {
          'id'      => action.id.to_s,
          '_method' => 'delete'
        }
        expect(last_response.status).to eq(302)
      end
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

      it 'renders the add-note form for a valid member action' do
        member    = create_member
        call_type = DB[:member_action_types].where(name: 'call_member').get(:id)
        action    = create_member_action(member: member, member_action_type_id: call_type)
        get '/m/member_action/add_note', 'mbr_action_id' => action.id.to_s, 'type' => 'call_member'
        expect(last_response.status).to eq(200)
      end
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

      it 'saves the note and redirects to the followup page' do
        member = create_member
        action = create_member_action(member: member)
        post '/m/member_action/add_note', {
          'mbr_action_id' => action.id.to_s,
          'note'          => 'A followup note'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end
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

      it 'creates the call-me record and redirects to the followup page' do
        member = create_member
        post '/m/mbr_callme/new', {
          'target_mbr_id' => member.id.to_s,
          'note'          => 'Please give this member a call',
          'mbr_tasked_to' => 'NONE'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end
    end

    describe 'GET /m/mbr_callme/edit/:id' do
      it 'renders the call-me edit form for a valid record' do
        member    = create_member
        call_type = DB[:member_action_types].where(name: 'call_member').get(:id)
        action    = create_member_action(member: member, member_action_type_id: call_type)
        get "/m/mbr_callme/edit/#{action.id}"
        expect(last_response.status).to eq(200)
      end
    end

    describe 'POST /m/mbr_callme/update/:id' do
      it 'updates the call-me record and redirects' do
        member    = create_member
        call_type = DB[:member_action_types].where(name: 'call_member').get(:id)
        action    = create_member_action(member: member, member_action_type_id: call_type)
        post "/m/mbr_callme/update/#{action.id}", {
          'id'               => action.id.to_s,
          'tasked_to_mbr_id' => '',
          'completed'        => '',
          'notes'            => 'updated call-me note'
        }
        expect(last_response.status).to eq(302)
        expect(last_response.location).to include('/m/followup/show')
      end

      it 'creates a log entry linked to the action via mbr_action_id when completing' do
        member    = create_member
        call_type = DB[:member_action_types].where(name: 'call_member').get(:id)
        action    = create_member_action(member: member, member_action_type_id: call_type)
        post "/m/mbr_callme/update/#{action.id}", {
          'id'               => action.id.to_s,
          'tasked_to_mbr_id' => '',
          'completed'        => 'true',
          'notes'            => 'called and spoke with member'
        }
        log = DB[:logs].where(mbr_action_id: action.id).first
        expect(log).not_to be_nil
        expect(log[:notes]).to include('completed')
      end
    end
  end
end
