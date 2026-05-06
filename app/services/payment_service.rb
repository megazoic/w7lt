require_relative '../../config/sequel'

module MemberTracker
  # Handles POST /m/payment/new business logic: dues renewals (including family unit
  # coordination and audit-log creation) and non-dues donations.
  #
  # Usage:
  #   result = PaymentService.call(params, session[:auth_user_id])
  #   session[:msg] = result.message
  #   redirect result.redirect_path
  class PaymentService
    Result = Struct.new(:ok?, :redirect_path, :message)

    # Raised inside DB.transaction to trigger rollback and carry the error result out.
    class ConflictError < StandardError
      attr_reader :redirect_path
      def initialize(msg, redirect_path)
        super(msg)
        @redirect_path = redirect_path
      end
    end

    def self.call(params, auth_user_id)
      new(params, auth_user_id).call
    end

    def call
      handle_callme

      if dues?
        early = prepare_dues
        return early if early
      else
        prepare_donation
      end

      pay = Payment.new(
        mbr_id:            @p["mbr_id"],
        a_user_id:         @uid,
        payment_type_id:   @p["payment_type"],
        payment_method_id: @p["payment_method"],
        payment_amount:    @pay_amt,
        ts:                Time.now
      )

      conflict = nil
      begin
        DB.transaction do
          if dues?
            begin
              persist_dues
            rescue ConflictError => e
              conflict = Result.new(false, e.redirect_path, e.message)
              raise Sequel::Rollback
            end
          end
          finalize_logs(pay)
        end
        return conflict if conflict
        Result.new(true, '/m/payments/show', 'Payment was successfully recorded')
      rescue StandardError => e
        warn "PaymentService #{e.class}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}"
        Result.new(false, '/m/payments/show', "The data was not entered successfully")
      end
    end

    private

    def initialize(params, auth_user_id)
      @p   = params
      @uid = auth_user_id
      @aug = (@p["notes"] || "").dup

      @log_pay    = Log.new(mbr_id: @p["mbr_id"], a_user_id: @uid, ts: Time.now)
      @log_unit   = Log.new(mbr_id: @p["mbr_id"], a_user_id: @uid, ts: Time.now,
                            action_id: Action.get_action_id("unit"))
      @log_action = Log.new(mbr_id: @p["mbr_id"], a_user_id: @uid, ts: Time.now,
                            action_id: Action.get_action_id("mbr_call_me"))

      @ach                    = {}
      @auditlog_hash          = {}
      @fam_mbr_ids            = []
      @mbr_family_unit_id     = nil
      @mbr_split_frm_fam_unit = false
      @al_save                = false
      @pay_amt                = nil
    end

    # ── Pre-transaction setup ────────────────────────────────────────────────

    def handle_callme
      return unless /leader\?\s+Yes/.match(@aug)
      DB[:member_actions].insert(
        member_action_type_id: 1,
        member_target:         @p["mbr_id"],
        a_user_id:             @uid,
        completed:             false,
        notes:                 "Jotform request for a call from club members",
        ts:                    DateTime.now
      )
      @log_action.notes = "Jotform request for a call from club members"
    end

    def prepare_dues
      @al_save = true
      m = Member[@p["mbr_id"]]

      if m.mbrship_renewal_date.nil?
        setup_new_member_ach
      else
        setup_returning_member_ach(m)
      end
      @log_pay.action_id = Action.get_action_id("mbr_renew")

      if @p["mbr_type"] == 'family'
        early = setup_family_payment(m)
        return early if early
      elsif @p["mbr_type_old"] == 'family'
        early = handle_family_split(m)
        return early if early
      end

      m.update(
        mbr_type:                 @ach["mbr_type"][1],
        mbrship_renewal_date:     @ach["mbrship_renewal_date"][1],
        mbrship_renewal_halt:     @ach["mbrship_renewal_halt"][1],
        mbrship_renewal_contacts: @ach["mbrship_renewal_contacts"][1],
        mbrship_renewal_active:   @ach["mbrship_renewal_active"][1]
      )

      @pay_amt = if @p.key?("other_pmt")
        @p["other_pmt"].to_i
      else
        Payment.fees[@p["mbr_type"]]
      end

      @aug << "\n" unless @aug.empty?
      if @ach["mbrship_renewal_date"][0] != @ach["mbrship_renewal_date"][1]
        @aug << "**** Mbrship renewal date changed from #{@ach["mbrship_renewal_date"][0]} to #{@ach["mbrship_renewal_date"][1]}"
      end
      if @p["mbr_type"] != @p["mbr_type_old"]
        @aug << "**** Member type changed from #{@p["mbr_type_old"]} to #{@p["mbr_type"]}"
      end
      nil
    end

    def setup_new_member_ach
      if ['honorary', 'lifetime'].include?(@p["mbr_type"])
        @ach["mbrship_renewal_date"] = ['nil', DateTime.new(2100, 1, 1)]
      else
        @ach["mbrship_renewal_date"] = ['nil', Time.now]
      end
      @ach["mbrship_renewal_halt"]     = ['nil', false]
      @ach["mbrship_renewal_active"]   = ['nil', false]
      @ach["mbrship_renewal_contacts"] = ['nil', 0]
      @ach["mbr_type"]                 = ['none', @p["mbr_type"]]
    end

    def setup_returning_member_ach(m)
      AuditLog::COLS_TO_TRACK.each do |mf|
        @ach[mf] = [m[mf.to_sym], nil] unless mf == "fam_unit_active"
      end
      unless @ach["mbrship_renewal_date"][0].is_a?(DateTime)
        @ach["mbrship_renewal_date"][0] = DateTime.parse(@ach["mbrship_renewal_date"][0].to_s)
      end
      @ach["mbrship_renewal_halt"][1]     = false
      @ach["mbrship_renewal_active"][1]   = false
      @ach["mbrship_renewal_contacts"][1] = 0
      @ach["mbrship_renewal_date"][1]     = MbrRenewal.getNewMbrshipRenewalDate(@p["mbr_id"], @p["mbr_type"])
      @ach["mbr_type"][1]                 = @p["mbr_type"]
    end

    def setup_family_payment(m)
      m.units.each do |mu|
        @mbr_family_unit_id = mu.id if mu.unit_type_id == UnitType.getID('family')
      end
      if @mbr_family_unit_id.nil?
        return Result.new(false, '/m/unit/create', 'Payment FAILED; please set up the family unit first')
      end
      @log_pay.unit_id  = @mbr_family_unit_id
      @log_unit.unit_id = @mbr_family_unit_id
      Unit[@mbr_family_unit_id].members.each do |f_member|
        @fam_mbr_ids << f_member.id if f_member.id.to_s != @p["mbr_id"]
      end
      nil
    end

    def handle_family_split(m)
      m.units.each do |mu|
        @mbr_family_unit_id = mu.id if mu.unit_type_id == UnitType.getID('family')
      end
      u = Unit[@mbr_family_unit_id]
      @log_pay.unit_id  = u.id
      @log_unit.unit_id = u.id

      if (Date.today.prev_year..Date.today).cover?(@ach["mbrship_renewal_date"][0].to_date)
        @aug << "\n" unless @aug.empty?
        if u.members.length < 3
          @aug << "\n****member currently paid up is trying to pay again*****\nRecord NOT updated"
          @log_pay.notes = @aug
          @log_pay.save
          return Result.new(false, '/r/member/list',
            "The data was not entered successfully\nthis member in fam unit that already paid")
        else
          @aug << "\n****member currently paid up is trying to pay again*****\nwill remove from fam unit"
          Unit[@mbr_family_unit_id].remove_member(m)
          @log_unit.notes = "Unit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed"
          @mbr_split_frm_fam_unit = true
        end
      else
        if u.members.length < 3
          old_name = u.name || 'null'
          u.name = "retired: #{u.name}, #{m.fname} #{m.lname}"
          @auditlog_hash["unit_name"] = build_al("name", old_name, u.name,
            unit_id: @mbr_family_unit_id, mbr_id: @p["mbr_id"])
          u.members.each do |m2|
            next if m2.id == @p["mbr_id"].to_i
            mc = Member[m2.id]
            if ['honorary', 'lifetime'].include?(@p["mbr_type"])
              mc.mbr_type = @p["mbr_type"]
              mc.mbrship_renewal_date = DateTime.new(2100, 1, 1)
            else
              mc.mbr_type = 'none'
            end
            mc.save
            @auditlog_hash["mbr_type2"] = build_al("mbr_type", "family", mc.mbr_type, mbr_id: m2.id)
          end
        elsif ['honorary', 'lifetime'].include?(@p["mbr_type"])
          u.members.each do |m2|
            mc = Member[m2.id]
            mc.mbr_type = @p["mbr_type"]
            mc.mbrship_renewal_date = DateTime.new(2100, 1, 1)
            mc.save
          end
        end
        @ach["fam_unit_active"] = [u.active, 0]
        u.active = 0
        u.save
        @mbr_split_frm_fam_unit = true
        u.remove_member(m)
        @log_unit.notes  = "Unit mbr association[-mbr_id:#{m.id}], #{m.fname} #{m.lname} has been removed\n"
        if @ach["fam_unit_active"][0] != 0
          @auditlog_hash["fam_unit_active"] = build_al(
            "fam_unit_active", @ach["fam_unit_active"][0], @ach["fam_unit_active"][1],
            mbr_id: @p["mbr_id"], unit_id: u.id
          )
        end
        @log_unit.notes << "unit id: #{u.id} active status has gone from #{@ach["fam_unit_active"][0]} to 0"
      end
      nil
    end

    def prepare_donation
      @log_pay.action_id = Action.get_action_id("donation")
      @pay_amt = @p["nonDues_pmt"]
    end

    # ── Inside DB.transaction ────────────────────────────────────────────────

    def persist_dues
      close_open_non_renewal_followups
      if ['honorary', 'lifetime', 'family'].include?(@p["mbr_type"])
        update_family_members
      end
      write_paying_member_audit_logs
      @log_unit.save if @p["mbr_type"] == 'family' || @p["mbr_type_old"] == 'family'
      Member[@p["mbr_id"]].save
    end

    def update_family_members
      return unless resolve_family_membership

      fam_names = ""
      @fam_mbr_ids.each do |fid|
        fm = Member[fid]
        rd = fm.mbrship_renewal_date
        if rd
          mrd = DateTime.parse(rd.to_s)
          if mrd > @ach["mbrship_renewal_date"][1]
            m = Member[@p["mbr_id"]]
            raise ConflictError.new(
              "UNSUCCESSFUL; family mbr #{fm.fname} #{fm.lname}: mbrship renewal date, " \
              "#{fm.mbrship_renewal_date} conflicts with #{m.fname} #{m.lname}: " \
              "mbrship renewal date #{m.mbrship_renewal_date}",
              '/m/unit/list/family'
            )
          end
        end
        fam_names << "\nmbr_id#:#{fm.id}, #{fm.fname}, #{fm.lname}"
        if fm.mbr_type != 'family' && fm.mbr_type != 'none'
          fm.mbr_type = 'family'
          al = AuditLog.new
          AuditLog::COLS_TO_TRACK.each do |ctt|
            next if ctt == "fam_unit_active"
            al.set("a_user_id" => @uid, "column" => ctt, "changed_date" => Time.now,
                   "old_value" => fm[ctt.to_sym], "new_value" => @ach[ctt][1], "mbr_id" => fm.id)
          end
          @auditlog_hash["#{fm.id}_mbr_mbr_type"] = al
        elsif fm.mbr_type == 'none'
          @auditlog_hash["#{fm.id}_mbr_mbr_type"] = build_al("mbr_type", 'none', 'family', mbr_id: fm.id)
        end
        fm.update(
          mbr_type:                 @ach["mbr_type"][1],
          mbrship_renewal_date:     @ach["mbrship_renewal_date"][1],
          mbrship_renewal_halt:     @ach["mbrship_renewal_halt"][1],
          mbrship_renewal_contacts: @ach["mbrship_renewal_contacts"][1],
          mbrship_renewal_active:   @ach["mbrship_renewal_active"][1]
        )
        fm.save
      end

      @log_unit.notes = @fam_mbr_ids.empty? ?
        "there is only one member of this family, sad" :
        "#{fam_names.sub("\n", '')} were also updated"

      fu = Unit[@mbr_family_unit_id]
      if fu.active == 0
        @auditlog_hash["fam_unit_active"] = build_al("fam_unit_active", 0, 1)
      end
      fu.active = 1
      fu.save
    end

    def resolve_family_membership
      return true if @p["mbr_type"] == 'family'
      mus = Member[@p["mbr_id"]].units
      return false if mus.nil? || mus.empty?
      mus.each do |mu|
        if mu.unit_type_id == UnitType.getID('family')
          @mbr_family_unit_id = mu.id
          Unit[@mbr_family_unit_id].members.each do |f_member|
            @fam_mbr_ids << f_member.id if f_member.id.to_s != @p["mbr_id"]
          end
          return true
        end
      end
      false
    end

    def write_paying_member_audit_logs
      @ach.each do |k, v|
        if k != "fam_unit_active" && @ach["mbr_type"][0] != "none"
          if v[0] != v[1]
            @auditlog_hash[k] = build_al(k, v[0], v[1], mbr_id: @p["mbr_id"])
          end
          if k == "mbr_type" && @mbr_split_frm_fam_unit
            @auditlog_hash["dropped_unit"] = build_al(
              "dropped_unit", @mbr_family_unit_id, "none",
              unit_id: @mbr_family_unit_id, mbr_id: @p["mbr_id"]
            )
          end
        elsif @ach["mbr_type"][0] == "none"
          @auditlog_hash["mbr_type"] = build_al(
            "mbr_type", @ach["mbr_type"][0], @ach["mbr_type"][1], mbr_id: @p["mbr_id"]
          )
        end
      end
    end

    def finalize_logs(pay)
      @aug << "\nPayment Log Association[unit_log_id:#{@log_unit.id}]" unless @log_unit.id.nil?
      @log_pay.notes = @aug
      @log_pay.save
      pay[:log_id] = @log_pay.values[:id]
      pay.save
      @log_action.save if !@log_action.notes.nil? && @log_action.notes != ""
      return unless @al_save
      @auditlog_hash.each do |_k, v|
        next if v.a_user_id.nil?
        v.pay_id  = pay.id
        v.unit_id = @mbr_family_unit_id if @p["mbr_type"] == 'family'
        v.save
      end
    end

    # ── Helpers ──────────────────────────────────────────────────────────────

    def close_open_non_renewal_followups
      nrf_type_id = MemberActionType[name: 'non_renew_followup'].id
      open_actions = MemberAction.where(
        member_target:         @p["mbr_id"],
        member_action_type_id: nrf_type_id,
        completed:             false
      ).all
      return if open_actions.empty?

      log_action_id = Action.get_action_id('member_not_renew_followup')
      open_actions.each do |ma|
        DB[:member_actions].where(id: ma.id).update(completed: true)
        Log.new(
          mbr_id:        @p["mbr_id"],
          a_user_id:     @uid,
          ts:            Time.now,
          action_id:     log_action_id,
          mbr_action_id: ma.id,
          notes:         "Non-renewal followup auto-completed: member recorded a dues payment"
        ).save
      end
    end

    def dues?
      PaymentType[@p["payment_type"]].type == 'Dues'
    end

    def build_al(column, old_val, new_val, mbr_id: nil, unit_id: nil)
      al = AuditLog.new
      attrs = { "a_user_id" => @uid, "column" => column, "changed_date" => Time.now,
                "old_value" => old_val, "new_value" => new_val }
      attrs["mbr_id"]  = mbr_id  if mbr_id
      attrs["unit_id"] = unit_id if unit_id
      al.set(attrs)
      al
    end
  end
end
