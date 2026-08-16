const STORAGE_KEY = 'ikars-instructor-demo-workspace-v1'

function clone(value) {
  return JSON.parse(JSON.stringify(value))
}

export function createDemoRepository(seed) {
  let workspace = clone(seed)

  function readStoredWorkspace() {
    try {
      const stored = JSON.parse(localStorage.getItem(STORAGE_KEY) || 'null')
      if (!stored || !Array.isArray(stored.students) || !Array.isArray(stored.lessons)) return null
      return { ...workspace, ...stored, instructor: stored.instructor || workspace.instructor, calendarBlocks: Array.isArray(stored.calendarBlocks) ? stored.calendarBlocks : [] }
    } catch {
      return null
    }
  }

  function persist() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(workspace))
  }

  return {
    mode: 'demo',
    async loadStudentPersonalSchedule() { return null },
    async createStudentScheduleLink() { throw new Error('STUDENT_SCHEDULE_REQUIRES_PRO') },
    async revokeStudentScheduleLink() {},
    async loadStudentScheduleSettings() { return { enabled: false, showFullHistory: true } },
    async saveStudentScheduleVisibility() {},
    async getSession() {
      return { user: { id: 'demo-instructor', email: 'demo@ikars.lv' }, demo: true }
    },
    async loadWorkspace() {
      workspace = readStoredWorkspace() || workspace
      return clone({ ...workspace, schoolInvitations: workspace.schoolInvitations || [] })
    },
    async respondToSchoolInvitation(linkId) {
      workspace.schoolInvitations = (workspace.schoolInvitations || []).filter((item) => item.linkId !== linkId)
      persist()
      return {}
    },
    async loadPublicDirectory() {
      return clone(workspace.publicInstructors || [])
    },
    async loadSchoolWidget(schoolSlug) {
      return { school: { name: schoolSlug || 'Partneru autoskola', logoUrl: null, settings: {} }, instructors: clone(workspace.publicInstructors || []) }
    },
    async loadSchoolStatistics(schoolSlug, days = 30) {
      return {
        school: { name: schoolSlug || 'Partneru autoskola', slug: schoolSlug }, periodDays: days,
        widgetViews: 48, profileViews: 21, phoneClicks: 7, filterUses: 12, activeSeconds: 2840, uniqueSessions: 35,
        instructors: (workspace.publicInstructors || []).map((item, index) => ({ id: item.id, name: item.name, profileViews: Math.max(2, 12 - index * 3), phoneClicks: Math.max(0, 4 - index) })),
      }
    },
    async loadSchoolManagement(schoolSlug) {
      return { school: { name: schoolSlug || 'Partneru autoskola', slug: schoolSlug, role: 'admin', settings: workspace.schoolWidgetSettings || {} }, instructors: (workspace.publicInstructors || []).map((item) => ({ linkId: item.id, instructorId: item.id, name: item.name, email: '', phone: item.phone, status: 'active', showInWidget: true, isPublic: true, profileStatus: 'active' })) }
    },
    async saveSchoolWidgetSettings(_schoolSlug, settings) { workspace.schoolWidgetSettings = clone(settings); persist(); return clone(settings) },
    async inviteSchoolInstructor() { return {} },
    async manageSchoolInstructor() { return {} },
    async recordPublicEvent() {},
    async saveLesson(lesson) {
      const index = workspace.lessons.findIndex((item) => item.id === lesson.id)
      if (index >= 0) workspace.lessons[index] = clone(lesson)
      else workspace.lessons.push(clone(lesson))
      persist()
      return clone(lesson)
    },
    async recordStudentAdvance(studentId, advance) {
      const student = workspace.students.find((item) => item.id === studentId)
      if (!student) throw new Error('Student not found')
      student.advancePayments ||= []
      student.advancePayments.unshift({ id: crypto.randomUUID(), student_id: studentId, amount: Number(advance.amount), method: advance.method, paid_at: new Date(`${advance.paidAt}T12:00:00`).toISOString(), note: advance.note || null })
      student.advanceBalance = Number(student.advanceBalance || 0) + Number(advance.amount)
      student.paid = Number(student.paid || 0) + Number(advance.amount)
      persist()
    },
    async voidStudentAdvancePayment(paymentId) {
      const student = workspace.students.find((item) => item.advancePayments?.some((payment) => payment.id === paymentId))
      const payment = student?.advancePayments.find((item) => item.id === paymentId)
      if (!student || !payment) return
      student.advancePayments = student.advancePayments.filter((item) => item.id !== paymentId)
      student.advanceBalance = Math.max(Number(student.advanceBalance || 0) - Number(payment.amount), 0)
      student.paid = Math.max(Number(student.paid || 0) - Number(payment.amount), 0)
      persist()
    },
    async saveStudent(student) {
      const index = workspace.students.findIndex((item) => item.id === student.id)
      if (index >= 0) workspace.students[index] = clone(student)
      else workspace.students.push(clone(student))
      persist()
      return clone(student)
    },
    async saveInstructorProfile(profile) {
      workspace.instructor = { ...workspace.instructor, ...clone(profile), name: `${profile.firstName} ${profile.lastName}`.trim() }
      persist()
      return clone(workspace.instructor)
    },
    async uploadInstructorPhoto(file) {
      const photoUrl = URL.createObjectURL(file)
      workspace.instructor = { ...workspace.instructor, photoUrl }
      return photoUrl
    },
    async deleteInstructorPhoto() {
      workspace.instructor = { ...workspace.instructor, photoUrl: '' }
      persist()
    },
    async saveVehicle(vehicle) {
      workspace.instructor.vehicles ||= []
      const saved = { ...clone(vehicle), id: vehicle.id || crypto.randomUUID(), name: `${vehicle.make} ${vehicle.model}`.trim(), isActive: vehicle.isActive !== false }
      const index = workspace.instructor.vehicles.findIndex((item) => item.id === saved.id)
      if (index >= 0) workspace.instructor.vehicles[index] = saved
      else workspace.instructor.vehicles.push(saved)
      persist()
      return clone(saved)
    },
    async saveMeetingPoint(point) {
      workspace.instructor.meetingPoints ||= []
      const saved = { ...clone(point), id: point.id || crypto.randomUUID(), label: [point.district, point.name].filter(Boolean).join(' — '), isActive: point.isActive !== false, showInWidget: Boolean(point.showInWidget) }
      const index = workspace.instructor.meetingPoints.findIndex((item) => item.id === saved.id)
      if (index >= 0) workspace.instructor.meetingPoints[index] = saved
      else workspace.instructor.meetingPoints.push(saved)
      if (workspace.instructor.meetingPoints.length === 1) saved.showInWidget = true
      persist()
      return clone(saved)
    },
    async saveCalendarBlock(block) {
      workspace.calendarBlocks ||= []
      workspace.calendarBlocks.push(clone(block))
      persist()
      return clone(block)
    },
    async deleteCalendarBlock(blockId) {
      workspace.calendarBlocks ||= []
      workspace.calendarBlocks = workspace.calendarBlocks.filter((item) => item.id !== blockId)
      persist()
    },
    async saveAvailabilitySettings(settings) {
      workspace.availabilitySettings = clone(settings)
      persist()
      return clone(settings)
    },
    async selectPublicMeetingPoint(pointId) {
      workspace.instructor.meetingPoints.forEach((point) => { point.showInWidget = point.id === pointId })
      persist()
    },
    async archiveMeetingPoint(pointId) {
      workspace.instructor.meetingPoints = workspace.instructor.meetingPoints.filter((point) => point.id !== pointId)
      persist()
    },
    async saveAnalytics(analytics) {
      workspace.analytics = clone(analytics)
      persist()
      return clone(analytics)
    },
  }
}
