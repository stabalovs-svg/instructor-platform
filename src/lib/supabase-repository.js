function requireUser(session) {
  if (!session?.user?.id) throw new Error('Authentication is required.')
  return session.user.id
}

import { runtimeConfig } from './runtime-config'

function mapInstructor(profile) {
  return {
    id: profile.id,
    firstName: profile.first_name,
    lastName: profile.last_name,
    name: `${profile.first_name} ${profile.last_name}`.trim(),
    phone: profile.phone || '',
    email: profile.email || '',
    languages: profile.languages || ['lv'],
    categories: profile.categories || ['B'],
    isPublic: Boolean(profile.is_public),
    publicPhone: profile.public_phone !== false,
    photoUrl: profile.photo_url || '',
    vehicles: (profile.vehicles || []).filter((vehicle) => vehicle.is_active !== false).map((vehicle) => ({
      id: vehicle.id,
      make: vehicle.make,
      model: vehicle.model,
      name: `${vehicle.make} ${vehicle.model}`,
      year: vehicle.production_year,
      transmission: vehicle.transmission === 'automatic' ? 'A' : 'M',
      price: Number(vehicle.lesson_price),
      weekendPrice: vehicle.weekend_price == null ? null : Number(vehicle.weekend_price),
      registrationNumber: vehicle.registration_number || '',
      isActive: vehicle.is_active,
    })),
    meetingPoints: (profile.meeting_points || []).filter((point) => point.is_active !== false).map((point) => ({
      id: point.id,
      city: point.city,
      district: point.district || '',
      name: point.public_name,
      label: [point.district, point.public_name].filter(Boolean).join(' — '),
      directions: point.directions || '',
      surcharge: Number(point.surcharge || 0),
      isActive: point.is_active,
      showInWidget: Boolean(point.show_in_widget),
    })),
  }
}

function zonedParts(value) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Riga', year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(value))
  return Object.fromEntries(parts.filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]))
}

function localTimeToIso(date, time) {
  const [year, month, day] = date.split('-').map(Number)
  const [hour, minute] = time.split(':').map(Number)
  const assumedUtc = Date.UTC(year, month - 1, day, hour, minute)
  const local = zonedParts(assumedUtc)
  const representedUtc = Date.UTC(Number(local.year), Number(local.month) - 1, Number(local.day), Number(local.hour), Number(local.minute))
  return new Date(assumedUtc - (representedUtc - assumedUtc)).toISOString()
}

function mapStudent(student, paid = 0, advanceBalance = 0, advancePayments = []) {
  return {
    id: student.id,
    firstName: student.first_name,
    lastName: student.last_name,
    phone: student.phone || '',
    email: student.email || '',
    school: student.school_name || '',
    vehicleId: student.preferred_vehicle_id,
    transmission: student.vehicles?.transmission === 'automatic' ? 'A' : 'M',
    price: student.lesson_price == null ? 0 : Number(student.lesson_price),
    paid,
    advanceBalance,
    advancePayments,
    lessons: 0,
    status: student.status,
    notes: student.notes || '',
  }
}

function mapLesson(lesson, payment = null) {
  const start = zonedParts(lesson.starts_at)
  const end = zonedParts(lesson.ends_at)
  const studentName = [lesson.students?.first_name, lesson.students?.last_name].filter(Boolean).join(' ')
  const vehicleName = lesson.vehicles ? `${lesson.vehicles.transmission === 'automatic' ? 'A' : 'M'} · ${lesson.vehicles.model}` : '—'
  const pointLabel = lesson.meeting_points ? [lesson.meeting_points.district, lesson.meeting_points.public_name].filter(Boolean).join(' — ') : '—'
  return {
    id: lesson.id,
    date: `${start.year}-${start.month}-${start.day}`,
    time: `${start.hour}:${start.minute}`,
    end: `${end.hour}:${end.minute}`,
    student: studentName,
    studentId: lesson.student_id,
    vehicle: vehicleName,
    vehicleId: lesson.vehicle_id,
    point: pointLabel,
    meetingPointId: lesson.meeting_point_id,
    price: Number(lesson.price),
    status: lesson.status,
    chargeable: lesson.chargeable,
    paymentId: payment?.id || null,
    paymentStatus: payment ? 'paid' : 'unpaid',
    paymentMethod: payment?.method || 'cash',
    note: lesson.note || '',
  }
}

function mapCalendarBlock(block) {
  const start = zonedParts(block.starts_at)
  const end = zonedParts(block.ends_at)
  return { id: block.id, date: `${start.year}-${start.month}-${start.day}`, time: `${start.hour}:${start.minute}`, end: `${end.hour}:${end.minute}`, reason: block.reason || '' }
}

function mapAvailabilityRule(rule) {
  if (!rule) return null
  const weekdays = rule.enabled_weekdays || [1, 2, 3, 4, 5]
  return {
    workStart: String(rule.first_lesson).slice(0, 5),
    workEnd: String(rule.last_lesson).slice(0, 5),
    slotMinutes: Number(rule.slot_minutes),
    saturdayEnabled: weekdays.includes(6),
    sundayEnabled: weekdays.includes(0),
    freeColorMode: rule.free_color,
    busyColorMode: rule.busy_color,
  }
}

const lessonSelect = '*, students!lessons_student_id_fkey(first_name,last_name), vehicles!lessons_vehicle_id_fkey(model,transmission), meeting_points!lessons_meeting_point_id_fkey(public_name,district)'

export function createSupabaseRepository(client) {
  async function getSession() {
    const { data, error } = await client.auth.getSession()
    if (error) throw error
    return data.session
  }

  async function currentInstructorId() {
    const session = await getSession()
    const userId = requireUser(session)
    const { data, error } = await client
      .from('instructor_profiles')
      .select('id')
      .eq('user_id', userId)
      .single()
    if (error) throw error
    return data.id
  }

  return {
    mode: 'supabase',
    getSession,
    async signIn(email, password) {
      const { data, error } = await client.auth.signInWithPassword({ email, password })
      if (error) throw error
      return data.session
    },
    async signOut() {
      const { error } = await client.auth.signOut()
      if (error) throw error
    },
    async loadPublicDirectory(startDate, days = 14) {
      const { data, error } = await client.rpc('get_public_instructor_directory', {
        p_start_date: startDate,
        p_days: days,
      })
      if (error) throw error
      return Array.isArray(data) ? data : []
    },
    async loadStudentPersonalSchedule(token) {
      const [scheduleResult, financeResult] = await Promise.all([
        client.rpc('get_student_personal_schedule_v2', { p_token: token }),
        client.rpc('get_student_personal_finance_v2', { p_token: token }),
      ])
      if (scheduleResult.error) throw scheduleResult.error
      if (financeResult.error) throw financeResult.error
      if (!scheduleResult.data) return null
      return { ...scheduleResult.data, statistics: { ...scheduleResult.data.statistics, ...financeResult.data } }
    },
    async createStudentScheduleLink(studentId) {
      const { data, error } = await client.rpc('create_student_schedule_link', { p_student_id: studentId })
      if (error) throw error
      return data
    },
    async revokeStudentScheduleLink(studentId) {
      const { error } = await client.rpc('revoke_student_schedule_link', { p_student_id: studentId })
      if (error) throw error
    },
    async loadStudentScheduleSettings(studentId) {
      const { data, error } = await client.rpc('get_student_schedule_settings', { p_student_id: studentId })
      if (error) throw error
      return data || { enabled: false, showFullHistory: true }
    },
    async saveStudentScheduleVisibility(studentId, showFullHistory) {
      const { error } = await client.rpc('set_student_schedule_visibility', {
        p_student_id: studentId,
        p_show_full_history: Boolean(showFullHistory),
      })
      if (error) throw error
    },
    async loadSchoolWidget(schoolSlug, startDate, days = 14) {
      const { data, error } = await client.rpc('get_school_instructor_widget', {
        p_school_slug: schoolSlug,
        p_start_date: startDate,
        p_days: days,
      })
      if (error) throw error
      return data
    },
    async loadSchoolStatistics(schoolSlug, days = 30) {
      const { data, error } = await client.rpc('get_my_school_widget_statistics', {
        p_school_slug: schoolSlug,
        p_days: days,
      })
      if (error) throw error
      if (!data) throw new Error('School statistics are not available for this account.')
      return data
    },
    async loadSchoolManagement(schoolSlug) {
      const { data, error } = await client.rpc('get_my_school_instructor_management', { p_school_slug: schoolSlug })
      if (error) throw error
      if (!data) throw new Error('School management is not available for this account.')
      return data
    },
    async saveSchoolWidgetSettings(schoolSlug, settings) {
      const { data, error } = await client.rpc('update_my_school_widget_settings', { p_school_slug: schoolSlug, p_settings: settings })
      if (error) throw error
      return data
    },
    async inviteSchoolInstructor(schoolSlug, email) {
      const { data, error } = await client.rpc('invite_school_instructor', { p_school_slug: schoolSlug, p_instructor_email: email })
      if (error) throw error
      return data
    },
    async manageSchoolInstructor(schoolSlug, linkId, action) {
      const { data, error } = await client.rpc('manage_school_instructor', { p_school_slug: schoolSlug, p_link_id: linkId, p_action: action })
      if (error) throw error
      return data
    },
    async loadPlatformAdminDashboard() {
      const { data, error } = await client.rpc('get_platform_admin_dashboard')
      if (error) throw error
      return data
    },
    async loadPlatformPlanPrices() {
      const { data, error } = await client.rpc('get_platform_plan_prices')
      if (error) throw error
      return data || []
    },
    async savePlatformPlanPrices(prices) {
      const { data, error } = await client.rpc('save_platform_plan_prices', { p_prices: prices })
      if (error) throw error
      return data || []
    },
    async createPlatformSchool(school) {
      const { data, error } = await client.rpc('platform_create_driving_school', {
        p_name: school.name,
        p_slug: school.slug,
        p_admin_email: school.adminEmail,
        p_registration_number: school.registrationNumber || null,
        p_email: school.email || null,
        p_phone: school.phone || null,
        p_website_url: school.websiteUrl || null,
      })
      if (error) throw error
      return data
    },
    async savePlatformSubscription(instructorId, subscription) {
      const { data, error } = await client.rpc('save_platform_instructor_subscription_v2', {
        p_instructor_id: instructorId,
        p_plan: subscription.plan,
        p_status: subscription.status,
        p_paid_at: subscription.paidAt || null,
        p_period_months: Number(subscription.periodMonths),
        p_paid_amount: Number(subscription.paidAmount),
        p_custom_total_amount: subscription.customPriceEnabled ? Number(subscription.customAmount) : null,
        p_note: subscription.note || null,
      })
      if (error) throw error
      return data
    },
    async grantPlatformSubscriptionGrace(instructorId, days, note = '') {
      const { data, error } = await client.rpc('grant_platform_subscription_grace', { p_instructor_id: instructorId, p_days: Number(days), p_note: note || null })
      if (error) throw error
      return data
    },
    async managePlatformSubscriptionTermination(instructorId, effectiveOn, exportAccessUntil, note = '') {
      const { data, error } = await client.rpc('manage_platform_subscription_termination', {
        p_instructor_id: instructorId,
        p_effective_on: effectiveOn || null,
        p_export_access_until: exportAccessUntil || null,
        p_note: note || null,
      })
      if (error) throw error
      return data
    },
    async resolvePlatformPaymentClaim(claimId, status, note = '') {
      const { data, error } = await client.rpc('resolve_platform_payment_claim', { p_claim_id: claimId, p_status: status, p_note: note || null })
      if (error) throw error
      return data
    },
    async loadMySubscriptionAccess() {
      const { data, error } = await client.rpc('get_my_subscription_access')
      if (error) throw error
      return data
    },
    async submitSubscriptionPaymentClaim(note = '') {
      const { data, error } = await client.rpc('submit_subscription_payment_claim', { p_note: note || null })
      if (error) throw error
      return data
    },
    async dismissSubscriptionNotification(notificationId) {
      const { data, error } = await client.rpc('dismiss_my_subscription_notification', { p_notification_id: notificationId })
      if (error) throw error
      return data
    },
    recordPublicEvent(event) {
      const body = JSON.stringify({
        p_event_type: event.type,
        p_session_id: event.sessionId,
        p_source: event.source,
        p_school_slug: event.schoolSlug || null,
        p_instructor_id: event.instructorId || null,
        p_active_seconds: event.activeSeconds ?? null,
        p_language: event.language,
        p_device_type: event.deviceType,
        p_metadata: event.metadata || {},
      })
      return fetch(`${runtimeConfig.supabaseUrl}/rest/v1/rpc/record_public_widget_event`, {
        method: 'POST', keepalive: true, body,
        headers: { apikey: runtimeConfig.supabasePublishableKey, Authorization: `Bearer ${runtimeConfig.supabasePublishableKey}`, 'Content-Type': 'application/json' },
      }).then((response) => { if (!response.ok) throw new Error(`Analytics request failed: ${response.status}`) })
    },
    async loadWorkspace() {
      const instructorId = await currentInstructorId()
      const [profileResult, studentsResult, lessonsResult, paymentsResult, allocationsResult, blocksResult, availabilityResult, analyticsResult, invitationsResult] = await Promise.all([
        client.from('instructor_profiles').select('*, vehicles(*), meeting_points(*)').eq('id', instructorId).single(),
        client.from('students').select('*, vehicles!students_preferred_vehicle_id_fkey(transmission)').eq('instructor_id', instructorId).order('last_name'),
        client.from('lessons').select(lessonSelect).eq('instructor_id', instructorId).order('starts_at'),
        client.from('payments').select('*').eq('instructor_id', instructorId).is('voided_at', null).order('paid_at', { ascending: false }),
        client.from('student_advance_allocations').select('*').eq('instructor_id', instructorId).is('voided_at', null),
        client.from('calendar_blocks').select('*').eq('instructor_id', instructorId).order('starts_at'),
        client.from('availability_rules').select('*').eq('instructor_id', instructorId).maybeSingle(),
        client.rpc('get_my_public_statistics', { p_days: 30 }),
        client.rpc('get_my_school_invitations'),
      ])
      if (profileResult.error) throw profileResult.error
      if (studentsResult.error) throw studentsResult.error
      if (lessonsResult.error) throw lessonsResult.error
      if (paymentsResult.error) throw paymentsResult.error
      if (allocationsResult.error) throw allocationsResult.error
      if (blocksResult.error) throw blocksResult.error
      if (availabilityResult.error) throw availabilityResult.error
      if (analyticsResult.error) throw analyticsResult.error
      if (invitationsResult.error) throw invitationsResult.error
      const paymentByLesson = new Map()
      for (const payment of paymentsResult.data) {
        if (payment.lesson_id && !paymentByLesson.has(payment.lesson_id)) paymentByLesson.set(payment.lesson_id, payment)
      }
      for (const allocation of allocationsResult.data) {
        if (!paymentByLesson.has(allocation.lesson_id)) paymentByLesson.set(allocation.lesson_id, { id: allocation.id, method: 'advance', amount: allocation.amount })
      }
      const mappedLessons = lessonsResult.data.map((lesson) => mapLesson(lesson, paymentByLesson.get(lesson.id)))
      const mappedStudents = studentsResult.data.map((student) => mapStudent(
        student,
        paymentsResult.data.filter((payment) => payment.student_id === student.id).reduce((total, payment) => total + Number(payment.amount), 0),
        Math.max(
          paymentsResult.data.filter((payment) => payment.student_id === student.id && !payment.lesson_id).reduce((total, payment) => total + Number(payment.amount), 0)
          - allocationsResult.data.filter((allocation) => allocation.student_id === student.id).reduce((total, allocation) => total + Number(allocation.amount), 0),
          0,
        ),
        paymentsResult.data.filter((payment) => payment.student_id === student.id && !payment.lesson_id),
      )).map((student) => ({
        ...student,
        lessons: mappedLessons.filter((lesson) => lesson.studentId === student.id && ['completed', 'no_show'].includes(lesson.status)).length,
      }))
      return { instructor: mapInstructor(profileResult.data), students: mappedStudents, lessons: mappedLessons, calendarBlocks: blocksResult.data.map(mapCalendarBlock), availabilitySettings: mapAvailabilityRule(availabilityResult.data), analytics: analyticsResult.data, schoolInvitations: invitationsResult.data || [] }
    },
    async respondToSchoolInvitation(linkId, response) {
      const { data, error } = await client.rpc('respond_to_school_invitation', { p_link_id: linkId, p_response: response })
      if (error) throw error
      return data
    },
    async saveInstructorProfile(profile) {
      const instructorId = await currentInstructorId()
      const { data, error } = await client.from('instructor_profiles').update({
        first_name: profile.firstName.trim(),
        last_name: profile.lastName.trim(),
        phone: profile.phone.trim() || null,
        languages: profile.languages,
        categories: profile.categories,
        is_public: Boolean(profile.isPublic),
        public_phone: profile.publicPhone !== false,
      }).eq('id', instructorId).select().single()
      if (error) throw error
      return { ...profile, id: data.id, firstName: data.first_name, lastName: data.last_name, name: `${data.first_name} ${data.last_name}`.trim(), phone: data.phone || '', languages: data.languages, categories: data.categories, isPublic: data.is_public, publicPhone: data.public_phone }
    },
    async uploadInstructorPhoto(file) {
      const instructorId = await currentInstructorId()
      const session = await getSession()
      const path = `${requireUser(session)}/profile.webp`
      const { error: uploadError } = await client.storage.from('instructor-photos').upload(path, file, { contentType: 'image/webp', upsert: true, cacheControl: '3600' })
      if (uploadError) throw uploadError
      const { data: publicData } = client.storage.from('instructor-photos').getPublicUrl(path)
      const photoUrl = `${publicData.publicUrl}?v=${Date.now()}`
      const { error: updateError } = await client.from('instructor_profiles').update({ photo_url: photoUrl }).eq('id', instructorId)
      if (updateError) throw updateError
      return photoUrl
    },
    async deleteInstructorPhoto() {
      const instructorId = await currentInstructorId()
      const session = await getSession()
      const path = `${requireUser(session)}/profile.webp`
      const { error: removeError } = await client.storage.from('instructor-photos').remove([path])
      if (removeError) throw removeError
      const { error: updateError } = await client.from('instructor_profiles').update({ photo_url: null }).eq('id', instructorId)
      if (updateError) throw updateError
    },
    async saveVehicle(vehicle) {
      const instructorId = await currentInstructorId()
      const record = {
        instructor_id: instructorId,
        make: vehicle.make.trim(), model: vehicle.model.trim(),
        production_year: vehicle.year || null,
        transmission: vehicle.transmission === 'A' ? 'automatic' : 'manual',
        registration_number: vehicle.registrationNumber.trim() || null,
        lesson_price: Number(vehicle.price),
        weekend_price: vehicle.weekendPrice === '' || vehicle.weekendPrice == null ? null : Number(vehicle.weekendPrice),
        is_active: vehicle.isActive !== false,
      }
      if (vehicle.id) record.id = vehicle.id
      const { data, error } = await client.from('vehicles').upsert(record).select().single()
      if (error) throw error
      return mapInstructor({ first_name: '', last_name: '', vehicles: [data], meeting_points: [] }).vehicles[0]
    },
    async saveMeetingPoint(point) {
      const instructorId = await currentInstructorId()
      const record = {
        instructor_id: instructorId,
        city: point.city.trim() || 'Rīga', district: point.district.trim() || null,
        public_name: point.name.trim(), directions: point.directions.trim() || null,
        surcharge: Number(point.surcharge || 0), is_active: point.isActive !== false,
      }
      if (point.id) record.id = point.id
      const { data, error } = await client.from('meeting_points').upsert(record).select().single()
      if (error) throw error
      return mapInstructor({ first_name: '', last_name: '', vehicles: [], meeting_points: [data] }).meetingPoints[0]
    },
    async selectPublicMeetingPoint(pointId) {
      const { error } = await client.rpc('select_public_meeting_point', { p_meeting_point_id: pointId })
      if (error) throw error
    },
    async archiveMeetingPoint(pointId) {
      const { error } = await client.rpc('archive_meeting_point', { p_meeting_point_id: pointId })
      if (error) throw error
    },
    async saveLesson(lesson) {
      const instructorId = await currentInstructorId()
      const session = await getSession()
      const names = lesson.student.trim().split(/\s+/)
      const firstName = names.shift() || ''
      const lastName = names.join(' ')
      let studentId = lesson.studentId || null
      if (studentId) {
        const { error: updateStudentError } = await client.from('students').update({ first_name: firstName, last_name: lastName }).eq('id', studentId).eq('instructor_id', instructorId)
        if (updateStudentError) throw updateStudentError
      } else {
        const { data: existing, error: findError } = await client.from('students').select('id').eq('instructor_id', instructorId).eq('first_name', firstName).eq('last_name', lastName).maybeSingle()
        if (findError) throw findError
        if (existing) studentId = existing.id
        else {
          const { data: created, error: createError } = await client.from('students').insert({ instructor_id: instructorId, first_name: firstName, last_name: lastName, preferred_vehicle_id: lesson.vehicleId, lesson_price: Number(lesson.price) }).select('id').single()
          if (createError) throw createError
          studentId = created.id
        }
      }
      const record = {
        instructor_id: instructorId,
        student_id: studentId,
        vehicle_id: lesson.vehicleId,
        meeting_point_id: lesson.meetingPointId,
        starts_at: localTimeToIso(lesson.date, lesson.time),
        ends_at: localTimeToIso(lesson.date, lesson.end),
        status: lesson.status,
        chargeable: Boolean(lesson.chargeable),
        price: Number(lesson.price),
        note: lesson.note || null,
        created_by: session.user.id,
      }
      if (typeof lesson.id === 'string' && /^[0-9a-f-]{36}$/i.test(lesson.id)) record.id = lesson.id
      const { data, error } = await client.from('lessons').upsert(record).select(lessonSelect).single()
      if (error) throw error
      const { data: activePayment, error: paymentLookupError } = await client.from('payments')
        .select('*').eq('instructor_id', instructorId).eq('lesson_id', data.id).is('voided_at', null)
        .order('paid_at', { ascending: false }).limit(1).maybeSingle()
      if (paymentLookupError) throw paymentLookupError

      const { data: activeAllocation, error: allocationLookupError } = await client.from('student_advance_allocations')
        .select('*').eq('instructor_id', instructorId).eq('lesson_id', data.id).is('voided_at', null).maybeSingle()
      if (allocationLookupError) throw allocationLookupError

      let payment = activePayment
      if (lesson.paymentStatus === 'paid' && lesson.paymentMethod === 'advance') {
        if (activePayment) {
          const { error: voidPaymentError } = await client.from('payments').update({
            voided_at: new Date().toISOString(), voided_by: session.user.id,
            void_reason: 'Payment source changed to student advance',
          }).eq('id', activePayment.id).eq('instructor_id', instructorId)
          if (voidPaymentError) throw voidPaymentError
        }
        const { data: allocationId, error: allocationError } = await client.rpc('allocate_student_advance', { p_lesson_id: data.id })
        if (allocationError) throw allocationError
        payment = { id: allocationId, method: 'advance', amount: Number(lesson.price) }
      } else if (lesson.paymentStatus === 'paid') {
        if (activeAllocation) {
          const { error: voidAllocationError } = await client.rpc('void_student_advance_allocation', {
            p_lesson_id: data.id, p_reason: 'Payment source changed to direct payment',
          })
          if (voidAllocationError) throw voidAllocationError
        }
        const paymentRecord = {
          instructor_id: instructorId,
          student_id: studentId,
          lesson_id: data.id,
          amount: Number(lesson.price),
          method: lesson.paymentMethod || 'cash',
        }
        if (activePayment) {
          const { data: updatedPayment, error: updatePaymentError } = await client.from('payments')
            .update(paymentRecord).eq('id', activePayment.id).eq('instructor_id', instructorId).select().single()
          if (updatePaymentError) throw updatePaymentError
          payment = updatedPayment
        } else {
          const { data: createdPayment, error: createPaymentError } = await client.from('payments')
            .insert({ ...paymentRecord, created_by: session.user.id }).select().single()
          if (createPaymentError) throw createPaymentError
          payment = createdPayment
        }
      } else {
        if (activePayment) {
          const { error: voidPaymentError } = await client.from('payments').update({
          voided_at: new Date().toISOString(),
          voided_by: session.user.id,
          void_reason: 'Payment status changed to unpaid in lesson form',
        }).eq('id', activePayment.id).eq('instructor_id', instructorId)
          if (voidPaymentError) throw voidPaymentError
        }
        if (activeAllocation) {
          const { error: voidAllocationError } = await client.rpc('void_student_advance_allocation', {
            p_lesson_id: data.id, p_reason: 'Lesson payment status changed to unpaid',
          })
          if (voidAllocationError) throw voidAllocationError
        }
        payment = null
      }
      return mapLesson(data, payment)
    },
    async recordStudentAdvance(studentId, advance) {
      const { data, error } = await client.rpc('record_student_advance', {
        p_student_id: studentId,
        p_amount: Number(advance.amount),
        p_method: advance.method,
        p_paid_at: advance.paidAt ? new Date(`${advance.paidAt}T12:00:00`).toISOString() : new Date().toISOString(),
        p_note: advance.note || null,
      })
      if (error) throw error
      return data
    },
    async voidStudentAdvancePayment(paymentId, reason) {
      const { error } = await client.rpc('void_student_advance_payment', { p_payment_id: paymentId, p_reason: reason })
      if (error) throw error
    },
    async saveStudent(student) {
      const instructorId = await currentInstructorId()
      const record = {
        instructor_id: instructorId,
        first_name: student.firstName.trim(),
        last_name: student.lastName.trim(),
        phone: student.phone.trim() || null,
        email: student.email.trim() || null,
        school_name: student.school.trim() || null,
        preferred_vehicle_id: student.vehicleId || null,
        lesson_price: Number(student.price),
        notes: student.notes.trim() || null,
        status: student.status,
      }
      if (typeof student.id === 'string' && /^[0-9a-f-]{36}$/i.test(student.id)) record.id = student.id
      const { data, error } = await client.from('students').upsert(record).select('*, vehicles!students_preferred_vehicle_id_fkey(transmission)').single()
      if (error) throw error
      return mapStudent(data)
    },
    async saveCalendarBlock(block) {
      const instructorId = await currentInstructorId()
      const { data, error } = await client.from('calendar_blocks').insert({ instructor_id: instructorId, starts_at: localTimeToIso(block.date, block.time), ends_at: localTimeToIso(block.date, block.end), reason: block.reason || null }).select().single()
      if (error) throw error
      return mapCalendarBlock(data)
    },
    async deleteCalendarBlock(blockId) {
      const instructorId = await currentInstructorId()
      const { error } = await client.from('calendar_blocks').delete().eq('id', blockId).eq('instructor_id', instructorId)
      if (error) throw error
    },
    async saveAvailabilitySettings(settings) {
      const instructorId = await currentInstructorId()
      const enabledWeekdays = [1, 2, 3, 4, 5]
      if (settings.saturdayEnabled) enabledWeekdays.push(6)
      if (settings.sundayEnabled) enabledWeekdays.unshift(0)
      const { data, error } = await client.from('availability_rules').upsert({
        instructor_id: instructorId,
        enabled_weekdays: enabledWeekdays,
        first_lesson: settings.workStart,
        last_lesson: settings.workEnd,
        slot_minutes: Number(settings.slotMinutes),
        free_color: settings.freeColorMode,
        busy_color: settings.busyColorMode,
      }, { onConflict: 'instructor_id' }).select().single()
      if (error) throw error
      return mapAvailabilityRule(data)
    },
    async saveAnalytics() {
      // Public widget analytics will be accepted by a dedicated Edge Function.
      // Direct anonymous writes to tables intentionally remain disabled.
    },
  }
}
