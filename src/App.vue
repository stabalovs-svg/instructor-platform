<script setup>
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { instructors, lessons, students } from './demo-data'
import { createRepository } from './lib/repository'

const DEMO_MONDAY = new Date('2026-08-10T12:00:00')
const LANGUAGE_STORAGE_KEY = 'ikars-instructor-language'
const CALENDAR_SETTINGS_STORAGE_KEY = 'ikars-instructor-calendar-settings'
let storedCalendarSettings = {}
try { storedCalendarSettings = JSON.parse(localStorage.getItem(CALENDAR_SETTINGS_STORAGE_KEY) || '{}') }
catch { storedCalendarSettings = {} }
const query = new URLSearchParams(window.location.search)
const forceOnboarding = query.get('onboarding') === '1'
const platformAdminMode = query.get('view') === 'platform-admin' && ['127.0.0.1', 'localhost'].includes(window.location.hostname)
const billingDemoState = ['7', '3', 'expired', 'termination'].includes(query.get('billing-demo')) && ['127.0.0.1', 'localhost'].includes(window.location.hostname) ? query.get('billing-demo') : ''
const widgetHashMatch = window.location.hash.match(/^#widget\/([a-z0-9-]+)(?:\/(banner|compact|full|cards))?$/i)
const studentHashMatch = window.location.hash.match(/^#student\/([a-f0-9]{64})$/i)
const studentScheduleMode = Boolean(studentHashMatch)
const studentScheduleToken = studentHashMatch?.[1] || ''
const publicWidgetMode = query.get('view') === 'widget' || Boolean(widgetHashMatch)
const publicDirectoryMode = query.get('view') === 'directory' || publicWidgetMode
const publicAccessMode = publicDirectoryMode || studentScheduleMode
const schoolDashboardMode = query.get('view') === 'school-statistics'
const widgetSchoolSlug = query.get('school') || widgetHashMatch?.[1] || ''
const requestedWidgetLayout = query.get('layout') || widgetHashMatch?.[2] || ''
const widgetLayoutExplicit = Boolean(requestedWidgetLayout)
const widgetLayout = ref(['banner', 'compact'].includes(requestedWidgetLayout) ? requestedWidgetLayout : 'full')
const PUBLIC_SESSION_KEY = 'ikars-public-session-id'
let publicSessionId = sessionStorage.getItem(PUBLIC_SESSION_KEY)
if (!publicSessionId) { publicSessionId = crypto.randomUUID(); sessionStorage.setItem(PUBLIC_SESSION_KEY, publicSessionId) }
const view = ref(studentScheduleMode ? 'student-schedule' : (publicDirectoryMode ? 'directory' : (schoolDashboardMode ? 'school-statistics' : (platformAdminMode ? 'platform-admin' : 'calendar'))))
const storedLanguage = localStorage.getItem(LANGUAGE_STORAGE_KEY)
const language = ref(storedLanguage === 'RU' ? 'RU' : 'LV')
const transmission = ref('ALL')
const district = ref('ALL')
const vehicleMake = ref('ALL')
const serviceType = ref('lesson')
const freeColorMode = ref(['mint', 'outline'].includes(storedCalendarSettings.freeColorMode) ? storedCalendarSettings.freeColorMode : 'outline')
const busyColorMode = ref(['warm', 'cool', 'pistachio', 'canary', 'peach'].includes(storedCalendarSettings.busyColorMode) ? storedCalendarSettings.busyColorMode : 'cool')
const saturdayEnabled = ref(storedCalendarSettings.saturdayEnabled ?? true)
const sundayEnabled = ref(storedCalendarSettings.sundayEnabled ?? false)
const workStart = ref(storedCalendarSettings.workStart || '06:00')
const workEnd = ref(storedCalendarSettings.workEnd || '21:00')
const slotMinutes = ref([60, 90].includes(storedCalendarSettings.slotMinutes) ? storedCalendarSettings.slotMinutes : 90)
const studentSearch = ref('')
const studentRecords = ref(students.map((student) => ({ ...student })))
const studentDialog = ref(false)
const studentForm = ref(null)
const studentLessonsVisible = ref(false)
const studentSchedule = ref(null)
const studentScheduleError = ref(false)
const studentScheduleLink = ref('')
const studentScheduleBusy = ref(false)
const studentScheduleMessage = ref('')
const studentScheduleAccessExists = ref(false)
const studentScheduleShowFullHistory = ref(true)
const studentAdvanceForm = ref({ amount: '', method: 'cash', paidAt: new Date().toISOString().slice(0, 10), note: '' })
const studentAdvanceBusy = ref(false)
const studentAdvanceMessage = ref('')
const currentInstructor = ref({ ...instructors[0], firstName: 'Andris', lastName: 'Bērziņš' })
const selectedInstructor = ref(currentInstructor.value)
const enlargedPhoto = ref(null)
const publicInstructors = ref(instructors.map((instructor) => ({ ...instructor })))
const widgetSchool = ref(null)
const weekOffset = ref(0)
const activeDayIndex = ref(0)
const calendarScroll = ref(null)
const publicCalendarScroll = ref(null)
const schedule = ref([
  ...lessons.map((lesson) => ({ ...lesson, date: '2026-08-10' })),
  { id: 11, date: '2026-08-11', time: '16:30', end: '18:00', student: 'Rihards Zariņš', vehicle: 'M · Golf', price: 35, point: 'Centrs' },
  { id: 12, date: '2026-08-11', time: '18:00', end: '19:30', student: 'Līga Vītola', vehicle: 'A · Corolla', price: 40, point: 'Purvciems' },
  { id: 13, date: '2026-08-11', time: '19:30', end: '21:00', student: 'Artūrs Krūmiņš', vehicle: 'M · Golf', price: 35, point: 'Centrs' },
  { id: 18, date: '2026-08-11', time: '21:00', end: '22:30', student: 'Māra Bērziņa', vehicle: 'A · Corolla', price: 40, point: 'Purvciems' },
  { id: 14, date: '2026-08-12', time: '07:30', end: '09:00', student: 'Ieva Jansone', vehicle: 'A · Corolla', price: 40, point: 'Purvciems' },
  { id: 15, date: '2026-08-13', time: '10:30', end: '12:00', student: 'Roberts Siliņš', vehicle: 'M · Golf', price: 35, point: 'Centrs' },
  { id: 16, date: '2026-08-14', time: '09:00', end: '10:30', student: 'Kristīne Eglīte', vehicle: 'A · Corolla', price: 40, point: 'Purvciems' },
  { id: 17, date: '2026-08-15', time: '12:00', end: '13:30', student: 'Edgars Balodis', vehicle: 'M · Golf', price: 38, point: 'Centrs' },
])
const calendarBlocks = ref([])
const lessonDialog = ref(false)
const availabilityDialog = ref(false)
const availabilityInstructor = ref(null)
const lessonError = ref('')
const datePickerOpen = ref(false)
const datePickerMonth = ref(new Date(DEMO_MONDAY.getFullYear(), DEMO_MONDAY.getMonth(), 1, 12))
const lessonForm = ref({ id: null, date: '2026-08-10', time: '09:00', duration: 90, student: '', vehicleId: instructors[0].vehicles[0].id, price: instructors[0].vehicles[0].price, point: instructors[0].meetingPoints[0], status: 'planned', chargeable: false, paymentStatus: 'unpaid', paymentMethod: 'cash' })
const analytics = ref({ views: 0, profileViews: 0, phoneClicks: 0, catalogPhoneClicks: 0, widgetPhoneClicks: 0, activeSeconds: 0, periodDays: 30 })
const schoolAnalytics = ref(null)
const schoolManagement = ref(null)
const schoolInviteEmail = ref('')
const schoolManagementBusy = ref(false)
const schoolManagementMessage = ref('')
const schoolWidgetForm = ref({ layout: 'compact', theme: 'ikars', accentColor: '#0d827b', showPhotos: true })
const schoolWidgetSaved = ref(false)
const platformPlanFilter = ref('ALL')
const platformStatusFilter = ref('ALL')
const platformSchoolFilter = ref('ALL')
const platformExpiryFilter = ref('ALL')
const platformSearch = ref('')
const platformDemoSchools = reactive([
  { id: 'school-1', name: 'Partneru autoskola', city: 'Rīga', phone: '+371 20 111 222', email: 'info@partneru-autoskola.lv', instructors: 3, widget: 'compact', status: 'pilot' },
  { id: 'school-2', name: 'Demo autoskola', city: 'Rīga', phone: '+371 20 333 444', email: 'info@demo-autoskola.lv', instructors: 3, widget: 'banner', status: 'demo' },
])
const platformDemoInstructors = reactive([
  { id: 'instructor-1', name: 'Andris Bērziņš', phone: '+371 20 555 101', email: 'andris@example.lv', schools: ['Partneru autoskola', 'Demo autoskola'], plan: 'pro', status: 'active', paidAt: '2026-08-01', periodMonths: 1, paidThrough: '2026-09-01', paidAmount: 25, monthly: 25 },
  { id: 'instructor-2', name: 'Jānis Ozoliņš', phone: '+371 20 555 102', email: 'janis@example.lv', schools: ['Partneru autoskola'], plan: 'basic', status: 'active', paidAt: '2026-06-05', periodMonths: 3, paidThrough: '2026-09-05', paidAmount: 42, monthly: 14 },
  { id: 'instructor-3', name: 'Ilze Kalniņa', phone: '+371 20 555 103', email: 'ilze@example.lv', schools: ['Demo autoskola'], plan: 'basic', status: 'trial', paidAt: '2026-08-14', periodMonths: 0, paidThrough: '2026-08-28', paidAmount: 0, monthly: 0 },
  { id: 'instructor-4', name: 'Mārtiņš Liepa', phone: '+371 20 555 104', email: 'martins@example.lv', schools: ['Demo autoskola', 'Partneru autoskola'], plan: 'profile', status: 'active', paidAt: '—', periodMonths: 0, paidThrough: '—', paidAmount: 0, monthly: 0 },
  { id: 'instructor-5', name: 'Laura Vītola', phone: '+371 20 555 105', email: 'laura@example.lv', schools: [], plan: 'pro', status: 'paused', paidAt: '2026-02-10', periodMonths: 6, paidThrough: '2026-08-10', paidAmount: 132, monthly: 22 },
])
const selectedPlatformInstructor = ref(null)
const selectedPlatformSchool = ref(null)
const platformSubscriptionForm = ref({ plan: 'profile', status: 'trial', paidAt: '', periodMonths: 1, paidAmount: 0, customPriceEnabled: false, customAmount: 0, note: '' })
const showPlatformSchoolForm = ref(false)
const platformSchoolForm = ref({ name: '', slug: '', adminEmail: '', registrationNumber: '', email: '', phone: '', websiteUrl: '' })
const platformSchoolCreated = ref(false)
const platformTerminationForm = ref({ effectiveOn: '', exportAccessUntil: '', note: '' })
const platformSubscriptionSaved = ref(false)
const platformTerminationSaved = ref(false)
const platformPricesSaved = ref(false)
const platformPlanPrices = ref(['profile', 'basic', 'pro'].flatMap((plan) => [1, 3, 6, 12].map((periodMonths) => ({ plan, periodMonths, totalAmount: 0 }))))
const platformAuditLog = ref([])
const platformAdminError = ref('')
const platformAdminBusy = ref(false)
watch(schoolWidgetForm, () => { schoolWidgetSaved.value = false }, { deep: true })
watch(platformPlanPrices, () => { platformPricesSaved.value = false }, { deep: true })
const schoolInvitations = ref([])
const repository = createRepository({
  instructor: currentInstructor.value,
  students: studentRecords.value,
  lessons: schedule.value,
  calendarBlocks: calendarBlocks.value,
  publicInstructors: instructors,
  analytics: analytics.value,
})
const calendarAnchorMonday = repository.mode === 'demo' ? DEMO_MONDAY : mondayFor(new Date())
if (repository.mode !== 'demo') activeDayIndex.value = (new Date().getDay() + 6) % 7
const session = ref(null)
const dataReady = ref(false)
const authEmail = ref('')
const authPassword = ref('')
const authError = ref('')
const authBusy = ref(false)
const accountDialog = ref(false)
const onboardingDismissed = ref(false)
const accountBusy = ref(false)
const accountMessage = ref('')
const photoInput = ref(null)
const saveNotice = ref('')
const profileForm = ref(null)
const vehicleForm = ref(null)
const meetingPointForm = ref(null)
let activeStartedAt = 0
let saveNoticeTimer = null
const BACKUP_STORAGE_KEY = 'ikars-instructor-last-calendar-export'
const BACKUP_SNOOZE_KEY = 'ikars-instructor-backup-reminder-snoozed'
const BACKUP_REMINDER_DAYS = 30
const lastCalendarExport = ref(localStorage.getItem(BACKUP_STORAGE_KEY) || '')
const backupReminderSnoozedUntil = ref(localStorage.getItem(BACKUP_SNOOZE_KEY) || '')
const billingReminderDismissed = ref(false)
const PAYMENT_CLAIMS_STORAGE_KEY = 'ikars-local-payment-claims'
let storedPaymentClaims = []
try { storedPaymentClaims = JSON.parse(localStorage.getItem(PAYMENT_CLAIMS_STORAGE_KEY) || '[]') }
catch { storedPaymentClaims = [] }
const platformPaymentClaims = ref(storedPaymentClaims)
const billingPaymentReported = ref(platformPaymentClaims.value.some((item) => item.status === 'pending'))
const subscriptionAccess = ref(null)
const billingNotification = ref(null)
const effectiveBillingState = computed(() => billingDemoState || ({ seven_days: '7', three_days: '3', expired: 'expired', termination: 'termination' }[billingNotification.value?.kind] || ''))
const billingReadOnly = computed(() => billingDemoState ? ['expired', 'termination'].includes(billingDemoState) : subscriptionAccess.value?.calendarWritable === false)
const billingExportAllowed = computed(() => billingDemoState ? billingDemoState !== 'expired' : subscriptionAccess.value?.exportAllowed !== false)
const showBillingNotice = computed(() => Boolean(effectiveBillingState.value) && !(effectiveBillingState.value === '7' && (billingReminderDismissed.value || billingNotification.value?.dismissedAt)))
const exportToday = new Date()
const exportMonday = new Date(exportToday); exportMonday.setHours(12, 0, 0, 0); exportMonday.setDate(exportToday.getDate() - ((exportToday.getDay() + 6) % 7))
const exportSunday = new Date(exportMonday); exportSunday.setDate(exportMonday.getDate() + 6)
const exportDateFrom = ref(isoDate(exportMonday))
const exportDateTo = ref(isoDate(exportSunday))
let activeTimer
let widgetResizeObserver
let publicActiveSeconds = 0

watch(language, (value) => localStorage.setItem(LANGUAGE_STORAGE_KEY, value))
watch([freeColorMode, busyColorMode, saturdayEnabled, sundayEnabled, workStart, workEnd, slotMinutes], () => {
  localStorage.setItem(CALENDAR_SETTINGS_STORAGE_KEY, JSON.stringify({
    freeColorMode: freeColorMode.value,
    busyColorMode: busyColorMode.value,
    saturdayEnabled: saturdayEnabled.value,
    sundayEnabled: sundayEnabled.value,
    workStart: workStart.value,
    workEnd: workEnd.value,
    slotMinutes: slotMinutes.value,
  }))
})

const copy = {
  LV: {
    calendar: 'Kalendārs', students: 'Audzēkņi', directory: 'Braukšanas instruktori', statistics: 'Statistika', today: 'Šodien', free: 'Brīvs laiks', call: 'Zvanīt instruktoram', next: 'Tuvākais brīvais laiks', meeting: 'Tikšanās vietas', views: 'Skatījumi', profiles: 'Profilu skatījumi', calls: 'Tālruņa klikšķi', active: 'Aktīvais laiks', note: 'Klikšķis uz tālruņa nenozīmē apstiprinātu sarunu.', lesson: 'Nodarbība', exam: 'Eksāmens', chooseService: 'Ko jūs meklējat?', student: 'Audzēknis', start: 'Sākums', duration: 'Ilgums', vehicle: 'Automobilis', price: 'Cena', save: 'Saglabāt', cancel: 'Atcelt', conflict: 'Šajā laikā instruktoram jau ir cita nodarbība.', required: 'Norādiet audzēkņa vārdu.', morning: 'Rīts', evening: 'Vakars', available: 'Brīvs', full: 'Aizņemts', previousWeek: 'Iepriekšējā nedēļa', nextWeek: 'Nākamā nedēļa', showCalendar: 'Skatīt kalendāru', availableTimes: 'Brīvo laiku kalendārs', currentWeek: 'Šī nedēļa', followingWeek: 'Nākamā nedēļa', noAvailability: 'Brīvu laiku nav', close: 'Aizvērt', chooseDay: 'Nospiediet uz dienas, lai skatītu detalizētu sarakstu', wholeWeek: 'Nedēļas pārskats', allRiga: 'Visa Rīga', nearestFive: 'Tuvākie brīvie laiki', searchStudent: 'Meklēt pēc vārda vai tālruņa', school: 'Autoskola', phone: 'Tālrunis', email: 'E-pasts', status: 'Statuss', notes: 'Piezīmes', lessonsCount: 'Nodarbības', paid: 'Samaksāts', balance: 'Bilance', activeStatus: 'Aktīvs', pausedStatus: 'Pauze', lessonStatus: 'Nodarbības statuss', planned: 'Plānota', completed: 'Notikusi', cancelled: 'Atcelta', noShow: 'Neieradās', chargeable: 'Nodarbība tiek ieskaitīta un ir jāapmaksā', payment: 'Apmaksa', unpaid: 'Nav apmaksāta', paidStatus: 'Apmaksāta', paymentMethod: 'Apmaksas veids', cash: 'Skaidra nauda', transfer: 'Pārskaitījums', schoolPayment: 'Apmaksāts autoskolā', advance: 'Norakstīt no avansa', studentAdvance: 'Audzēkņa avanss', availableAdvance: 'Pieejamais avanss', recordAdvance: 'Iemaksāt avansu', advanceAmount: 'Saņemtā summa', advanceSaved: 'Avanss saglabāts.', advanceHistory: 'Avansa iemaksas', voidAdvance: 'Atcelt kļūdainu iemaksu', voidReason: 'Norādiet obligātu atcelšanas iemeslu:', insufficientAdvance: 'Avansā nepietiek līdzekļu šai nodarbībai.', allocatedAdvance: 'No avansa', lessonNote: 'Nodarbības piezīme', lessonHistory: 'Notikušo nodarbību saraksts', noLessons: 'Notikušu nodarbību vēl nav', noShowRule: 'Ja audzēknis neierodas un nav brīdinājis 24 stundas iepriekš, nodarbība tiek ieskaitīta un ir jāapmaksā.', colors: 'Kalendāra krāsas', freeStyle: 'Brīvs laiks', busyStyle: 'Aizņemts laiks', mint: 'Gaiši tirkīza', outline: 'Balts ar rāmi', warm: 'Silti pelēks', cool: 'Vēsi pelēks', months: ['janvārī','februārī','martā','aprīlī','maijā','jūnijā','jūlijā','augustā','septembrī','oktobrī','novembrī','decembrī'], weekdays: ['Svētdien','Pirmdien','Otrdien','Trešdien','Ceturtdien','Piektdien','Sestdien'], shortDays: ['Sv','P','O','T','C','P','S'], locale: 'lv-LV'
  },
  RU: {
    calendar: 'Календарь', students: 'Ученики', directory: 'Инструкторы по вождению', statistics: 'Статистика', today: 'Сегодня', free: 'Свободно', call: 'Позвонить инструктору', next: 'Ближайшее свободное время', meeting: 'Места встречи', views: 'Просмотры', profiles: 'Просмотры профилей', calls: 'Нажатия телефона', active: 'Активное время', note: 'Нажатие телефона не подтверждает состоявшийся разговор.', lesson: 'Занятие', exam: 'Экзамен', chooseService: 'Что вы ищете?', student: 'Ученик', start: 'Начало', duration: 'Длительность', vehicle: 'Автомобиль', price: 'Цена', save: 'Сохранить', cancel: 'Отмена', conflict: 'В это время у инструктора уже есть другое занятие.', required: 'Укажите имя ученика.', morning: 'Утро', evening: 'Вечер', available: 'Свободно', full: 'Занято', previousWeek: 'Предыдущая неделя', nextWeek: 'Следующая неделя', showCalendar: 'Посмотреть календарь', availableTimes: 'Календарь свободного времени', currentWeek: 'Эта неделя', followingWeek: 'Следующая неделя', noAvailability: 'Свободного времени нет', close: 'Закрыть', chooseDay: 'Нажмите на день, чтобы посмотреть подробное расписание', wholeWeek: 'Обзор недели', allRiga: 'Вся Рига', nearestFive: 'Ближайшее свободное время', searchStudent: 'Поиск по имени или телефону', school: 'Автошкола', phone: 'Телефон', email: 'Email', status: 'Статус', notes: 'Заметки', lessonsCount: 'Занятия', paid: 'Оплачено', balance: 'Баланс', activeStatus: 'Активен', pausedStatus: 'Пауза', lessonStatus: 'Статус занятия', planned: 'Запланировано', completed: 'Проведено', cancelled: 'Отменено', noShow: 'Не явился', chargeable: 'Занятие засчитывается и подлежит оплате', payment: 'Оплата', unpaid: 'Не оплачено', paidStatus: 'Оплачено', paymentMethod: 'Способ оплаты', cash: 'Наличные', transfer: 'Перечисление', schoolPayment: 'Оплачено в автошколе', advance: 'Списать из аванса', studentAdvance: 'Аванс ученика', availableAdvance: 'Доступный аванс', recordAdvance: 'Внести аванс', advanceAmount: 'Полученная сумма', advanceSaved: 'Аванс сохранён.', advanceHistory: 'Поступления аванса', voidAdvance: 'Отменить ошибочный платёж', voidReason: 'Укажите обязательную причину отмены:', insufficientAdvance: 'В авансе недостаточно средств для этого занятия.', allocatedAdvance: 'Из аванса', lessonNote: 'Примечание к занятию', lessonHistory: 'Список проведённых занятий', noLessons: 'Проведённых занятий пока нет', noShowRule: 'Если ученик не явился и не предупредил за 24 часа, занятие засчитывается и подлежит оплате.', colors: 'Цвета календаря', freeStyle: 'Свободное время', busyStyle: 'Занятое время', mint: 'Светло-бирюзовый', outline: 'Белый с рамкой', warm: 'Тёплый серый', cool: 'Холодный серый', months: ['января','февраля','марта','апреля','мая','июня','июля','августа','сентября','октября','ноября','декабря'], weekdays: ['Воскресенье','Понедельник','Вторник','Среда','Четверг','Пятница','Суббота'], shortDays: ['Вс','Пн','Вт','Ср','Чт','Пт','Сб'], locale: 'ru-RU'
  },
}
Object.assign(copy.LV, { date: 'Maksājuma datums' })
Object.assign(copy.RU, { date: 'Дата платежа' })
Object.assign(copy.LV, { settings: 'Kalendāra iestatījumi', workSettings: 'Darba laiks', firstLesson: 'Pirmā nodarbība', lastLesson: 'Pēdējā nodarbība', saturday: 'Sestdiena', sunday: 'Svētdiena', dayOff: 'Brīvdiena' })
Object.assign(copy.RU, { settings: 'Настройки календаря', workSettings: 'Рабочее время', firstLesson: 'Первое занятие', lastLesson: 'Последнее занятие', saturday: 'Суббота', sunday: 'Воскресенье', dayOff: 'Выходной' })
Object.assign(copy.LV, { blockSlot: 'Bloķēt laiku', unblockSlot: 'Atbloķēt', blockDay: 'Bloķēt dienu', unblockDay: 'Atbloķēt dienu', blocked: 'Nav pieejams' })
Object.assign(copy.RU, { blockSlot: 'Заблокировать время', unblockSlot: 'Разблокировать', blockDay: 'Заблокировать день', unblockDay: 'Разблокировать день', blocked: 'Недоступно' })
Object.assign(copy.LV, { pistachio: 'Pistāciju', canary: 'Kanāriju dzeltens', peach: 'Persiku' })
Object.assign(copy.RU, { pistachio: 'Фисташковый', canary: 'Канареечный', peach: 'Персиковый' })
Object.assign(copy.LV, { newCar: 'Pievienot automobili', newCarForm: 'Jauns automobilis', editCarForm: 'Automobiļa rediģēšana' })
Object.assign(copy.RU, { newCar: 'Добавить автомобиль', newCarForm: 'Новый автомобиль', editCarForm: 'Редактирование автомобиля' })
Object.assign(copy.LV, { schoolStatistics: 'Autoskola statistika', widgetViews: 'Logrīka atvēršanas', filterUses: 'Filtru lietojumi', uniqueVisitors: 'Unikālās sesijas', activeMinutes: 'Aktīvais laiks, min.', instructorResults: 'Rezultāti pa instruktoriem', noSchoolAccess: 'Šim kontam nav pieejama izvēlētās autoskolas statistika.', schoolStatsNote: 'Tālruņa klikšķis parāda mēģinājumu piezvanīt, nevis apstiprinātu sarunu.' })
Object.assign(copy.RU, { schoolStatistics: 'Статистика автошколы', widgetViews: 'Открытия виджета', filterUses: 'Использование фильтров', uniqueVisitors: 'Уникальные сессии', activeMinutes: 'Активное время, мин.', instructorResults: 'Результаты по инструкторам', noSchoolAccess: 'Этому пользователю недоступна статистика выбранной автошколы.', schoolStatsNote: 'Нажатие телефона показывает попытку позвонить, но не подтверждает состоявшийся разговор.' })
Object.assign(copy.LV, { schoolTeam: 'Instruktoru pārvaldība', inviteInstructor: 'Uzaicināt instruktoru', instructorEmail: 'Instruktora profila e-pasts', invitationPrepared: 'Uzaicinājums ir sagatavots. Instruktoram tas vēl jāpieņem.', managementError: 'Darbību neizdevās izpildīt.', visibleInWidget: 'Redzams logrīkā', hiddenInWidget: 'Paslēpts logrīkā', showInWidget: 'Rādīt logrīkā', hideFromWidget: 'Paslēpt', pauseLink: 'Apturēt', resumeLink: 'Atjaunot', endLink: 'Izbeigt sadarbību', confirmEndLink: 'Izbeigt sadarbību? Instruktora personīgie dati netiks dzēsti.', invitedLink: 'Uzaicināts', activeLink: 'Aktīvs', pausedLink: 'Apturēts', endedLink: 'Izbeigts', adminOnly: 'Instruktorus var pārvaldīt tikai autoskolas administrators.' })
Object.assign(copy.RU, { schoolTeam: 'Управление инструкторами', inviteInstructor: 'Пригласить инструктора', instructorEmail: 'Email из профиля инструктора', invitationPrepared: 'Приглашение подготовлено. Инструктор ещё должен его принять.', managementError: 'Не удалось выполнить действие.', visibleInWidget: 'Показывается в виджете', hiddenInWidget: 'Скрыт из виджета', showInWidget: 'Показывать', hideFromWidget: 'Скрыть', pauseLink: 'Приостановить', resumeLink: 'Возобновить', endLink: 'Прекратить сотрудничество', confirmEndLink: 'Прекратить сотрудничество? Личные данные инструктора удалены не будут.', invitedLink: 'Приглашён', activeLink: 'Активен', pausedLink: 'Приостановлен', endedLink: 'Завершён', adminOnly: 'Управлять инструкторами может только администратор автошколы.' })
Object.assign(copy.LV, { widgetSchoolLimit: 'Basic tarifs ļauj instruktoru publicēt tikai vienas autoskolas logrīkā. Vispirms paslēpiet instruktoru otrā autoskolā vai pārejiet uz Pro.', activeWidgetSchools: 'Aktīvie autoskolu logrīki' })
Object.assign(copy.RU, { widgetSchoolLimit: 'Тариф Basic позволяет публиковать инструктора в виджете только одной автошколы. Сначала скройте его в другой школе или перейдите на Pro.', activeWidgetSchools: 'Активные виджеты автошкол' })
Object.assign(copy.LV, { instructorEmailNotFound: 'Instruktora profils ar šo e-pastu nav atrasts. Pārbaudiet precīzu e-pastu viņa IKARS profilā.' })
Object.assign(copy.RU, { instructorEmailNotFound: 'Профиль инструктора с таким email не найден. Проверьте точный email в его профиле IKARS.' })
Object.assign(copy.LV, { planPricing: 'Tarifu cenas', planPricingHelp: 'Kopējā cena par izvēlēto periodu. Izmaiņas attieksies uz turpmākiem abonementiem.', totalPrice: 'Kopējā cena', savePlanPrices: 'Saglabāt cenas', planPricesSaved: 'Tarifu cenas saglabātas datubāzē.' })
Object.assign(copy.RU, { planPricing: 'Цены тарифов', planPricingHelp: 'Общая цена за выбранный период. Изменения применяются к будущим подпискам.', totalPrice: 'Общая цена', savePlanPrices: 'Сохранить цены', planPricesSaved: 'Цены тарифов сохранены в базе данных.' })
Object.assign(copy.LV, { subscriptionStandardPrice: 'Abonementa standarta cena', subscriptionAgreedPrice: 'Abonementa cena', useCustomPrice: 'Individuāla cena', customPrice: 'Individuālā cena', restoreStandardPrice: 'Izmantot standarta cenu' })
Object.assign(copy.RU, { subscriptionStandardPrice: 'Стандартная цена подписки', subscriptionAgreedPrice: 'Цена подписки', useCustomPrice: 'Индивидуальная цена', customPrice: 'Индивидуальная цена', restoreStandardPrice: 'Использовать стандартную цену' })
Object.assign(copy.LV, { paymentBalance: 'Atlikums apmaksai', markPaidInFull: 'Apmaksāts pilnībā', subscriptionUnpaid: 'Nav apmaksāts', subscriptionPartPaid: 'Daļēji apmaksāts', subscriptionPaid: 'Apmaksāts' })
Object.assign(copy.RU, { paymentBalance: 'Остаток к оплате', markPaidInFull: 'Оплачено полностью', subscriptionUnpaid: 'Не оплачено', subscriptionPartPaid: 'Частично оплачено', subscriptionPaid: 'Оплачено' })
Object.assign(copy.LV, { personalSchedule: 'Mans braukšanas grafiks', personalScheduleHelp: 'Jūsu personīgās nodarbības IKARS sistēmā', nextLessons: 'Nākamās nodarbības', pastLessons: 'Iepriekšējās nodarbības', completedLessons: 'Notikušās nodarbības', totalPaidByStudent: 'Kopā samaksāts', noUpcomingLessons: 'Nākamo nodarbību nav.', invalidStudentLink: 'Šī saite nav derīga vai tās piekļuve ir atsaukta.', createStudentLink: 'Izveidot audzēkņa saiti', replaceStudentLink: 'Izveidot jaunu saiti', revokeStudentLink: 'Atsaukt piekļuvi', copyStudentLink: 'Kopēt saiti', studentLinkCopied: 'Saite nokopēta.', studentLinkCreated: 'Personīgā saite ir izveidota. Nosūtiet to tikai šim audzēknim.', studentLinkRevoked: 'Piekļuve ir atsaukta.', studentScheduleProOnly: 'Personīgais grafiks ir pieejams Basic un Pro tarifā.', ikarsInfoPortal: 'IKARS informācijas portāls', ikarsInfoPortalHelp: 'Noderīga informācija Latvijas audzēkņiem un instruktoriem' })
Object.assign(copy.RU, { personalSchedule: 'Моё расписание вождения', personalScheduleHelp: 'Ваши личные занятия в системе IKARS', nextLessons: 'Ближайшие занятия', pastLessons: 'Прошедшие занятия', completedLessons: 'Проведено занятий', totalPaidByStudent: 'Всего оплачено', noUpcomingLessons: 'Будущих занятий пока нет.', invalidStudentLink: 'Ссылка недействительна или доступ к ней отозван.', createStudentLink: 'Создать ссылку ученика', replaceStudentLink: 'Создать новую ссылку', revokeStudentLink: 'Отозвать доступ', copyStudentLink: 'Копировать ссылку', studentLinkCopied: 'Ссылка скопирована.', studentLinkCreated: 'Персональная ссылка создана. Отправьте её только этому ученику.', studentLinkRevoked: 'Доступ отозван.', studentScheduleProOnly: 'Личное расписание доступно в тарифах Basic и Pro.', ikarsInfoPortal: 'Информационный портал IKARS', ikarsInfoPortalHelp: 'Полезная информация для учеников и инструкторов Латвии' })
Object.assign(copy.LV, { schoolInvitations: 'Autoskola uzaicinājumi', invitationText: 'Autoskola aicina jūs pievienoties tās instruktoru sarakstam.', acceptInvitation: 'Pieņemt', declineInvitation: 'Noraidīt', invitationAccepted: 'Uzaicinājums pieņemts. Autoskolas administrators tagad var jūs publicēt logrīkā.', invitationDeclined: 'Uzaicinājums noraidīts.' })
Object.assign(copy.RU, { schoolInvitations: 'Приглашения автошкол', invitationText: 'Автошкола приглашает вас присоединиться к списку её инструкторов.', acceptInvitation: 'Принять', declineInvitation: 'Отклонить', invitationAccepted: 'Приглашение принято. Теперь администратор автошколы сможет опубликовать вас в виджете.', invitationDeclined: 'Приглашение отклонено.' })
Object.assign(copy.LV, { lessonHistory: 'Visu nodarbību vēsture', noLessons: 'Šim audzēknim nodarbību vēl nav.', editLesson: 'Atvērt un labot' })
Object.assign(copy.RU, { lessonHistory: 'История всех занятий', noLessons: 'У этого ученика занятий пока нет.', editLesson: 'Открыть и изменить' })
Object.assign(copy.LV, { chargedTotal: 'Aprēķināts', debt: 'Parāds', credit: 'Avanss' })
Object.assign(copy.RU, { chargedTotal: 'Начислено', debt: 'Задолженность', credit: 'Аванс' })
Object.assign(copy.LV, { settlementClosed: 'Norēķins veikts' })
Object.assign(copy.RU, { settlementClosed: 'Расчёт закрыт' })
Object.assign(copy.LV, { studentVisibility: 'Ko redz audzēknis', studentFullView: 'Pilna informācija', studentFullViewHelp: 'Nākamās un iepriekšējās nodarbības, kopējie aprēķini un bilance.', studentBalanceView: 'Tikai grafiks un bilance', studentBalanceViewHelp: 'Nākamās nodarbības, neapmaksātās iepriekšējās nodarbības, parāds vai avanss.', studentVisibilitySaved: 'Audzēkņa skata iestatījums saglabāts.' })
Object.assign(copy.RU, { studentVisibility: 'Что видит ученик', studentFullView: 'Полная информация', studentFullViewHelp: 'Будущие и прошлые занятия, общие суммы и баланс.', studentBalanceView: 'Только расписание и баланс', studentBalanceViewHelp: 'Будущие занятия, прошлые неоплаченные занятия, долг или аванс.', studentVisibilitySaved: 'Настройка просмотра ученика сохранена.' })
Object.assign(copy.LV, { lessonSaved: 'Nodarbība un apmaksa ir saglabāta.', dataBackup: 'Kalendāra rezerves kopija', downloadCalendar: 'Lejupielādēt kalendāru XLS', backupReminder: 'Ieteicams lejupielādēt jaunu kalendāra rezerves kopiju.', lastBackup: 'Pēdējā kopija', neverExported: 'vēl nav lejupielādēta', exportReady: 'Kalendāra kopija ir lejupielādēta.' })
Object.assign(copy.RU, { lessonSaved: 'Занятие и оплата сохранены.', dataBackup: 'Резервная копия календаря', downloadCalendar: 'Скачать календарь XLS', backupReminder: 'Рекомендуется скачать новую резервную копию календаря.', lastBackup: 'Последняя копия', neverExported: 'ещё не скачивалась', exportReady: 'Копия календаря скачана.' })
Object.assign(copy.LV, { exportFrom: 'Periods no', exportTo: 'līdz', exportRangeError: 'Norādiet pareizu saglabāšanas periodu.' })
Object.assign(copy.RU, { exportFrom: 'Период с', exportTo: 'по', exportRangeError: 'Укажите правильный период сохранения.' })
Object.assign(copy.LV, { backupAlert: 'Izveidojiet kalendāra rezerves kopiju, lai jūsu grafiks būtu pieejams arī ārpus sistēmas.', downloadNow: 'Lejupielādēt', remindLater: 'Atgādināt pēc 7 dienām' })
Object.assign(copy.RU, { backupAlert: 'Создайте резервную копию календаря, чтобы расписание было доступно и вне системы.', downloadNow: 'Скачать', remindLater: 'Напомнить через 7 дней' })
Object.assign(copy.LV, { lessonDate: 'Nodarbības datums' })
Object.assign(copy.RU, { lessonDate: 'Дата занятия' })
Object.assign(copy.LV, { calendarPreferences: 'Kalendāra iestatījumi', standardDuration: 'Standarta nodarbība', minutesShort: 'min' })
Object.assign(copy.RU, { calendarPreferences: 'Настройки календаря', standardDuration: 'Стандартное занятие', minutesShort: 'мин' })
Object.assign(copy.LV, { account: 'Profils', firstName: 'Vārds', lastName: 'Uzvārds', cars: 'Automobiļi', addCar: 'Saglabāt automobili', make: 'Marka', model: 'Modelis', year: 'Gads', manual: 'Manuālā', automatic: 'Automātiskā', weekendPrice: 'Cena brīvdienās', registrationNumber: 'Reģistrācijas numurs', points: 'Tikšanās vietas', addPoint: 'Saglabāt vietu', city: 'Pilsēta', districtName: 'Rajons', publicName: 'Nosaukums klientam', surcharge: 'Piemaksa', directions: 'Norādes', saved: 'Saglabāts', noVehicle: 'Vispirms profilā pievienojiet automobili un tikšanās vietu.' })
Object.assign(copy.RU, { account: 'Профиль', firstName: 'Имя', lastName: 'Фамилия', cars: 'Автомобили', addCar: 'Сохранить автомобиль', make: 'Марка', model: 'Модель', year: 'Год', manual: 'Механика', automatic: 'Автомат', weekendPrice: 'Цена в выходные', registrationNumber: 'Регистрационный номер', points: 'Места встречи', addPoint: 'Сохранить место', city: 'Город', districtName: 'Район', publicName: 'Название для клиента', surcharge: 'Доплата', directions: 'Пояснение', saved: 'Сохранено', noVehicle: 'Сначала добавьте автомобиль и место встречи в профиле.' })
const t = computed(() => copy[language.value])
Object.assign(copy.LV, { edit: 'Labot', profileData: 'Instruktora dati', standardPrice: 'Nodarbības cena', saveError: 'Neizdevās saglabāt. Pārbaudiet laukus un mēģiniet vēlreiz.' })
Object.assign(copy.RU, { edit: 'Изменить', profileData: 'Данные инструктора', standardPrice: 'Цена за занятие', saveError: 'Не удалось сохранить. Проверьте поля и повторите.' })
Object.assign(copy.LV, { publicPreview: 'Publiskais katalogs', openPublicDirectory: 'Atvērt publisko katalogu', backToCabinet: 'Instruktora kabinets' })
Object.assign(copy.RU, { publicPreview: 'Публичный каталог', openPublicDirectory: 'Открыть публичный каталог', backToCabinet: 'Кабинет инструктора' })
Object.assign(copy.LV, { publishProfile: 'Rādīt publiskajā katalogā', publishPhone: 'Rādīt tālruni publiski', publicEmpty: 'Publisku instruktoru profilu vēl nav.' })
Object.assign(copy.RU, { publishProfile: 'Показывать в публичном каталоге', publishPhone: 'Показывать телефон публично', publicEmpty: 'Публичных профилей инструкторов пока нет.' })
Object.assign(copy.LV, { schoolWidget: 'Autoskolas instruktoru saraksts', schoolNotFound: 'Autoskola nav atrasta vai tās logrīks vēl nav aktivizēts.', poweredBy: 'Darbojas ar IKARS' })
Object.assign(copy.RU, { schoolWidget: 'Список инструкторов автошколы', schoolNotFound: 'Автошкола не найдена или её виджет ещё не активирован.', poweredBy: 'Работает на платформе IKARS' })
Object.assign(copy.LV, { widgetLocation: 'Rādīt logrīkā', deleteLocation: 'Dzēst', confirmDeleteLocation: 'Noņemt šo tikšanās vietu no aktīvā saraksta?' })
Object.assign(copy.RU, { widgetLocation: 'Показывать в виджете', deleteLocation: 'Удалить', confirmDeleteLocation: 'Убрать это место встречи из активного списка?' })
Object.assign(copy.LV, { teachingLanguages: 'Mācību valodas', drivingCategories: 'Kategorijas', chooseLanguageCategory: 'Izvēlieties vismaz vienu valodu un vienu kategoriju.' })
Object.assign(copy.RU, { teachingLanguages: 'Языки преподавания', drivingCategories: 'Категории', chooseLanguageCategory: 'Выберите хотя бы один язык и одну категорию.' })
Object.assign(copy.LV, { catalogCalls: 'No kopējā kataloga', widgetCalls: 'No autoskolas logrīka', lastDays: 'Pēdējās 30 dienas', instructorStatsNote: 'Tālruņa klikšķis nozīmē zvana mēģinājumu, nevis apstiprinātu sarunu.' })
Object.assign(copy.RU, { catalogCalls: 'Из общего каталога', widgetCalls: 'Из виджета автошколы', lastDays: 'Последние 30 дней', instructorStatsNote: 'Нажатие телефона означает попытку звонка, а не подтверждённый разговор.' })
Object.assign(copy.LV, { bannerTitle: 'Atrodiet piemērotu braukšanas instruktoru', bannerText: 'Izvēlieties valodu, automobili un tikšanās vietu, pēc tam apskatiet aktuālos brīvos laikus.', openInstructorList: 'Atrast instruktoru' })
Object.assign(copy.RU, { bannerTitle: 'Найдите подходящего инструктора по вождению', bannerText: 'Выберите язык, автомобиль и место встречи, затем посмотрите актуальное свободное время.', openInstructorList: 'Найти инструктора' })
Object.assign(copy.LV, { backToSchoolSite: 'Atgriezties autoskolas mājaslapā' })
Object.assign(copy.RU, { backToSchoolSite: 'Вернуться на сайт автошколы' })
Object.assign(copy.LV, { profilePhoto: 'Profila fotogrāfija', photoHelp: 'Portrets 4:5. JPG, PNG vai WebP, ne lielāks par 3 MB.', choosePhoto: 'Izvēlēties fotogrāfiju', photoSaved: 'Fotogrāfija ir saglabāta.', photoInvalid: 'Izvēlieties JPG, PNG vai WebP attēlu līdz 3 MB.' })
Object.assign(copy.RU, { profilePhoto: 'Фотография профиля', photoHelp: 'Портрет 4:5. JPG, PNG или WebP, не более 3 МБ.', choosePhoto: 'Выбрать фотографию', photoSaved: 'Фотография сохранена.', photoInvalid: 'Выберите изображение JPG, PNG или WebP размером до 3 МБ.' })
Object.assign(copy.LV, { deletePhoto: 'Dzēst fotogrāfiju', confirmDeletePhoto: 'Vai tiešām dzēst profila fotogrāfiju?', photoDeleted: 'Fotogrāfija ir dzēsta.' })
Object.assign(copy.RU, { deletePhoto: 'Удалить фотографию', confirmDeletePhoto: 'Удалить фотографию профиля?', photoDeleted: 'Фотография удалена.' })
Object.assign(copy.LV, { widgetAppearance: 'Logrīka noformējums', widgetLayoutLabel: 'Attēlošanas režīms', widgetThemeLabel: 'Krāsu tēma', customSchoolColor: 'Autoskolas krāsa', showInstructorPhotos: 'Rādīt instruktoru fotogrāfijas', hideInstructorPhotos: 'Nerādīt fotogrāfijas', preview: 'Priekšskatījums', openLargePreview: 'Atvērt lielo priekšskatījumu', backToSchoolCabinet: 'Atgriezties autoskolas kabinetā', saveAppearance: 'Saglabāt noformējumu', appearanceSaved: 'Logrīka noformējums ir saglabāts.', themeIkars: 'IKARS', themeBaltic: 'Baltic Blue', themeSand: 'Warm Sand', themeGraphite: 'Graphite' })
Object.assign(copy.RU, { widgetAppearance: 'Оформление виджета', widgetLayoutLabel: 'Режим отображения', widgetThemeLabel: 'Цветовая тема', customSchoolColor: 'Цвет автошколы', showInstructorPhotos: 'Показывать фотографии инструкторов', hideInstructorPhotos: 'Не показывать фотографии', preview: 'Предварительный просмотр', openLargePreview: 'Открыть большой предпросмотр', backToSchoolCabinet: 'Вернуться в кабинет автошколы', saveAppearance: 'Сохранить оформление', appearanceSaved: 'Оформление виджета сохранено.', themeIkars: 'IKARS', themeBaltic: 'Baltic Blue', themeSand: 'Warm Sand', themeGraphite: 'Graphite' })
Object.assign(copy.LV, { allVehicleMakes: 'Visas auto markas' })
Object.assign(copy.RU, { allVehicleMakes: 'Все марки автомобилей' })
Object.assign(copy.LV, { setupTitle: 'Sagatavojiet kalendāru darbam', setupText: 'Aizpildiet trīs pamatsoļus. Ievadītie dati tiek saglabāti jūsu profilā.', setupProfile: 'Instruktora dati', setupProfileHelp: 'Vārds, tālrunis, valodas un kategorijas', setupVehicle: 'Automobilis un cena', setupVehicleHelp: 'Vismaz viens aktīvs mācību automobilis', setupPoint: 'Tikšanās vieta', setupPointHelp: 'Vismaz viena vieta skolēniem', setupOpen: 'Turpināt iestatīšanu', setupDone: 'Sākotnējā iestatīšana ir pabeigta', setupClose: 'Sākt darbu' })
Object.assign(copy.RU, { setupTitle: 'Подготовьте календарь к работе', setupText: 'Выполните три основных шага. Введённые данные сохраняются в вашем профиле.', setupProfile: 'Данные инструктора', setupProfileHelp: 'Имя, телефон, языки и категории', setupVehicle: 'Автомобиль и цена', setupVehicleHelp: 'Хотя бы один активный учебный автомобиль', setupPoint: 'Место встречи', setupPointHelp: 'Хотя бы одно место для учеников', setupOpen: 'Продолжить настройку', setupDone: 'Первоначальная настройка завершена', setupClose: 'Начать работу' })
Object.assign(copy.LV, { platformAdmin: 'IKARS pārvaldība', platformOverview: 'Platformas pārskats', activeSubscriptions: 'Aktīvie abonementi', monthlyRevenue: 'Ikmēneša ieņēmumi', needsAttention: 'Jāpārbauda', schoolsCount: 'Autoskolas', platformSchools: 'Autoskolu reģistrs', platformInstructors: 'Instruktori un tarifi', platformInstructor: 'Instruktors', allPlans: 'Visi tarifi', allStatuses: 'Visi statusi', allSchools: 'Visas autoskolas', noSchool: 'Nav piesaistīts autoskolai', searchInstructor: 'Meklēt pēc vārda, tālruņa vai autoskolas', foundInstructors: 'Atrasti instruktori', linkedInstructors: 'Piesaistītie instruktori', cooperationSchools: 'Sadarbības autoskolas', widgetMode: 'Logrīka režīms', plan: 'Tarifs', renewal: 'Nākamais maksājums', monthlyPrice: 'Mēnesī', pilotStatus: 'Pilots', demoStatus: 'Demo', activeSubscription: 'Aktīvs', trialSubscription: 'Izmēģinājums', pausedSubscription: 'Apturēts', localPrototype: 'Lokāls prototips — dati netiek sūtīti uz Supabase' })
Object.assign(copy.RU, { platformAdmin: 'Управление IKARS', platformOverview: 'Обзор платформы', activeSubscriptions: 'Активные подписки', monthlyRevenue: 'Доход в месяц', needsAttention: 'Требуют внимания', schoolsCount: 'Автошколы', platformSchools: 'Реестр автошкол', platformInstructors: 'Инструкторы и тарифы', platformInstructor: 'Инструктор', allPlans: 'Все тарифы', allStatuses: 'Все статусы', allSchools: 'Все автошколы', noSchool: 'Не привязан к автошколе', searchInstructor: 'Поиск по имени, телефону или автошколе', foundInstructors: 'Найдено инструкторов', linkedInstructors: 'Связанные инструкторы', cooperationSchools: 'Автошколы сотрудничества', widgetMode: 'Режим виджета', plan: 'Тариф', renewal: 'Следующий платёж', monthlyPrice: 'В месяц', pilotStatus: 'Пилот', demoStatus: 'Демо', activeSubscription: 'Активен', trialSubscription: 'Пробный период', pausedSubscription: 'Приостановлен', localPrototype: 'Локальный прототип — данные не отправляются в Supabase' })
Object.assign(copy.LV, { addPlatformSchool: 'Pievienot autoskolu', newPlatformSchool: 'Jauna pilotprojekta autoskola', schoolSystemAddress: 'Sistēmas adrese', schoolAdminEmail: 'Direktora konta e-pasts', schoolRegistrationNumber: 'Reģistrācijas numurs', schoolWebsite: 'Mājaslapa', createPlatformSchool: 'Izveidot autoskolu', platformSchoolCreated: 'Autoskola un direktora piekļuve ir izveidota', schoolAdminHelp: 'Direktoram vispirms jāreģistrē lietotāja konts ar norādīto e-pastu.', schoolAdminMissing: 'Direktora konts ar šo e-pastu vēl nav reģistrēts.', schoolSlugExists: 'Autoskola ar šādu sistēmas adresi jau pastāv.' })
Object.assign(copy.RU, { addPlatformSchool: 'Добавить автошколу', newPlatformSchool: 'Новая пилотная автошкола', schoolSystemAddress: 'Системный адрес', schoolAdminEmail: 'Email аккаунта директора', schoolRegistrationNumber: 'Регистрационный номер', schoolWebsite: 'Сайт', createPlatformSchool: 'Создать автошколу', platformSchoolCreated: 'Автошкола и доступ директора созданы', schoolAdminHelp: 'Директор должен предварительно зарегистрировать пользовательский аккаунт с указанным email.', schoolAdminMissing: 'Аккаунт директора с этим email ещё не зарегистрирован.', schoolSlugExists: 'Автошкола с таким системным адресом уже существует.' })
Object.assign(copy.LV, { subscriptionManagement: 'Abonementa pārvaldība', adminNote: 'Administratora piezīme', adminNotePlaceholder: 'Izmaiņu iemesls vai komentārs', saveSubscription: 'Saglabāt abonementu', subscriptionSaved: 'Abonements saglabāts datubāzē.', adminHistory: 'Administratīvo izmaiņu žurnāls', noAdminHistory: 'Šajā sesijā izmaiņu vēl nav.' })
Object.assign(copy.RU, { subscriptionManagement: 'Управление подпиской', adminNote: 'Комментарий администратора', adminNotePlaceholder: 'Причина изменения или пояснение', saveSubscription: 'Сохранить подписку', subscriptionSaved: 'Подписка сохранена в базе данных.', adminHistory: 'Журнал административных изменений', noAdminHistory: 'В этой сессии изменений пока нет.' })
Object.assign(copy.LV, { paymentControl: 'Apmaksas periodu kontrole', lastPaymentDate: 'Apmaksas datums', paidPeriod: 'Apmaksātais periods', paidAmount: 'Samaksāts', paidThrough: 'Apmaksāts līdz', daysRemaining: 'Atlikušas dienas', monthsShort: 'mēn.', daysShort: 'dienas', expiringSoon: 'Beidzas vai nokavēts', expiryAll: 'Visi termiņi', expiry14: 'Līdz 14 dienām', expiry30: 'Līdz 30 dienām', expiryExpired: 'Nokavēts', expiredAgo: 'Nokavēts dienas' })
Object.assign(copy.RU, { paymentControl: 'Контроль оплаченных периодов', lastPaymentDate: 'Дата оплаты', paidPeriod: 'Оплаченный период', paidAmount: 'Оплачено', paidThrough: 'Оплачено до', daysRemaining: 'Осталось дней', monthsShort: 'мес.', daysShort: 'дн.', expiringSoon: 'Заканчиваются или просрочены', expiryAll: 'Все сроки', expiry14: 'До 14 дней', expiry30: 'До 30 дней', expiryExpired: 'Просрочено', expiredAgo: 'Просрочено дней' })
Object.assign(copy.LV, { billingSevenTitle: 'Abonements beigsies pēc 7 dienām', billingSevenText: 'Lūdzu, savlaicīgi pagariniet abonementu, lai kalendārs turpinātu darboties bez pārtraukuma.', billingThreeTitle: 'Abonements beigsies pēc 3 dienām', billingThreeText: 'Šo paziņojumu nevar aizvērt. Pēc termiņa kalendārs pāries tikai lasīšanas režīmā.', billingExpiredTitle: 'Kalendārs ir tikai lasīšanas režīmā', billingExpiredText: 'Apmaksas periods ir beidzies. Datus var apskatīt un lejupielādēt vēl 30 dienas, bet tos nevar mainīt.', billingTerminationTitle: 'Līguma izbeigšanas periods', billingTerminationText: 'Jaunus ierakstus nevar izveidot. Datu eksports ir atbloķēts līdz līgumā norādītajam datumam.', paymentReported: 'Maksājums paziņots — gaida pārbaudi', iPaid: 'Esmu samaksājis', dismissReminder: 'Atgādināt vēlāk', billingReadOnlyNotice: 'Apmaksas periods ir beidzies. Kalendārs pieejams tikai apskatei.', exportStillAvailable: 'Datu lejupielāde ir pieejama', previewBilling: 'Pārbaudīt instruktora paziņojumus', preview7: '7 dienas', preview3: '3 dienas', previewExpired: 'Nokavēts', previewTermination: 'Līguma izbeigšana' })
Object.assign(copy.RU, { billingSevenTitle: 'До окончания подписки осталось 7 дней', billingSevenText: 'Продлите подписку заранее, чтобы календарь продолжил работу без перерыва.', billingThreeTitle: 'До окончания подписки осталось 3 дня', billingThreeText: 'Это уведомление нельзя закрыть. После окончания срока календарь перейдёт в режим просмотра.', billingExpiredTitle: 'Календарь доступен только для просмотра', billingExpiredText: 'Оплаченный период закончился. Ещё 30 дней можно просматривать и скачивать данные, но нельзя их изменять.', billingTerminationTitle: 'Период расторжения договора', billingTerminationText: 'Новые записи отключены. Экспорт данных разблокирован до установленной договором даты.', paymentReported: 'Оплата заявлена — ожидается проверка', iPaid: 'Я оплатил', dismissReminder: 'Напомнить позже', billingReadOnlyNotice: 'Оплаченный период закончился. Календарь доступен только для просмотра.', exportStillAvailable: 'Скачивание данных доступно', previewBilling: 'Проверить уведомления инструктора', preview7: '7 дней', preview3: '3 дня', previewExpired: 'Просрочено', previewTermination: 'Расторжение' })
Object.assign(copy.LV, { billingExpiredText: 'Apmaksas periods ir beidzies. Datus var apskatīt, bet kalendāru mainīt un lejupielādēt nevar.', exportLocked: 'Datu lejupielāde ir bloķēta. Sazinieties ar IKARS administratoru.' })
Object.assign(copy.RU, { billingExpiredText: 'Оплаченный период закончился. Данные можно просматривать, но изменять и скачивать календарь нельзя.', exportLocked: 'Скачивание данных заблокировано. Обратитесь к администратору IKARS.' })
Object.assign(copy.LV, { terminationManagement: 'Līguma izbeigšana', terminationDate: 'Darbības izbeigšanas datums', exportAccessUntil: 'Lejupielāde atļauta līdz', scheduleTermination: 'Ieplānot izbeigšanu', cancelTermination: 'Atcelt izbeigšanu', terminationSaved: 'Izbeigšanas nosacījumi saglabāti', terminationCancelled: 'Izbeigšana atcelta', terminationHelp: 'Līdz norādītajam datumam kalendārs darbojas kā parasti. Pēc tam tas kļūst tikai lasāms; lejupielāde darbojas tikai līdz atļautajam datumam.' })
Object.assign(copy.RU, { terminationManagement: 'Расторжение договора', terminationDate: 'Дата прекращения работы', exportAccessUntil: 'Скачивание разрешено до', scheduleTermination: 'Назначить расторжение', cancelTermination: 'Отменить расторжение', terminationSaved: 'Условия расторжения сохранены', terminationCancelled: 'Расторжение отменено', terminationHelp: 'До указанной даты календарь работает обычно. После неё он доступен только для просмотра; скачивание действует только до разрешённой даты.' })
Object.assign(copy.LV, { paymentClaims: 'Maksājumu paziņojumi', paymentClaimPending: 'Gaida pārbaudi', paymentClaimConfirmed: 'Apstiprināts', paymentClaimRejected: 'Noraidīts', confirmPayment: 'Apstiprināt', rejectPayment: 'Noraidīt', noPaymentClaims: 'Nav jaunu maksājumu paziņojumu.', gracePeriod: 'Pagarinājums', grantGrace: 'Piešķirt pagarinājumu' })
Object.assign(copy.RU, { paymentClaims: 'Заявления об оплате', paymentClaimPending: 'Ожидает проверки', paymentClaimConfirmed: 'Подтверждено', paymentClaimRejected: 'Отклонено', confirmPayment: 'Подтвердить', rejectPayment: 'Отклонить', noPaymentClaims: 'Новых заявлений об оплате нет.', gracePeriod: 'Отсрочка', grantGrace: 'Предоставить отсрочку' })
const authCopy = computed(() => language.value === 'LV' ? {
  title: 'Instruktora kabinets', subtitle: 'Ievadiet savu e-pastu un paroli.', email: 'E-pasts', password: 'Parole', signIn: 'Pieteikties', signingIn: 'Pieslēdzas…', signOut: 'Iziet', loading: 'Ielādē…', genericError: 'Neizdevās pieteikties. Pārbaudiet e-pastu un paroli.'
} : {
  title: 'Кабинет инструктора', subtitle: 'Введите email и пароль.', email: 'Email', password: 'Пароль', signIn: 'Войти', signingIn: 'Выполняется вход…', signOut: 'Выйти', loading: 'Загрузка…', genericError: 'Не удалось войти. Проверьте email и пароль.'
})

function addDays(date, count) { const next = new Date(date); next.setDate(next.getDate() + count); return next }
function mondayFor(date) { const value = new Date(date); value.setHours(12, 0, 0, 0); return addDays(value, -((value.getDay() + 6) % 7)) }
function isoDate(date) { return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}` }
const weekStart = computed(() => addDays(calendarAnchorMonday, weekOffset.value * 7))
const weekDays = computed(() => Array.from({ length: 7 }, (_, index) => {
  const date = addDays(weekStart.value, index)
  return { date, iso: isoDate(date), label: t.value.shortDays[date.getDay()], number: date.getDate(), weekend: index > 4 }
}))
const activeDay = computed(() => weekDays.value[activeDayIndex.value])
const setupSteps = computed(() => {
  const instructor = currentInstructor.value || {}
  return [
    { key: 'profile', title: t.value.setupProfile, help: t.value.setupProfileHelp, ready: Boolean(instructor.firstName && instructor.lastName && instructor.phone && instructor.languages?.length && instructor.categories?.length) },
    { key: 'vehicle', title: t.value.setupVehicle, help: t.value.setupVehicleHelp, ready: Boolean(instructor.vehicles?.length) },
    { key: 'point', title: t.value.setupPoint, help: t.value.setupPointHelp, ready: Boolean(instructor.meetingPoints?.length) },
  ]
})
const setupComplete = computed(() => setupSteps.value.every((step) => step.ready))
const showSetupGuide = computed(() => !onboardingDismissed.value && (forceOnboarding || !setupComplete.value))
const filteredPlatformInstructors = computed(() => {
  const search = platformSearch.value.trim().toLocaleLowerCase()
  return platformDemoInstructors.filter((item) => {
    const matchesPlan = platformPlanFilter.value === 'ALL' || item.plan === platformPlanFilter.value
    const matchesStatus = platformStatusFilter.value === 'ALL' || item.status === platformStatusFilter.value
    const matchesSchool = platformSchoolFilter.value === 'ALL' || (platformSchoolFilter.value === 'NONE' ? item.schools.length === 0 : item.schools.includes(platformSchoolFilter.value))
    const days = platformDaysLeft(item)
    const matchesExpiry = platformExpiryFilter.value === 'ALL' || (platformExpiryFilter.value === 'EXPIRED' ? days !== null && days < 0 : days !== null && days >= 0 && days <= Number(platformExpiryFilter.value))
    const matchesSearch = !search || `${item.name} ${item.phone} ${item.email} ${item.schools.join(' ')}`.toLocaleLowerCase().includes(search)
    return matchesPlan && matchesStatus && matchesSchool && matchesExpiry && matchesSearch
  })
})
const platformMetrics = computed(() => ({
  subscriptions: platformDemoInstructors.filter((item) => item.status === 'active' && item.monthly > 0).length,
  revenue: platformDemoInstructors.filter((item) => item.status === 'active').reduce((sum, item) => sum + item.monthly, 0),
  attention: platformDemoInstructors.filter((item) => ['trial', 'paused'].includes(item.status)).length,
  expiring: platformDemoInstructors.filter((item) => { const days = platformDaysLeft(item); return days !== null && days <= 14 }).length,
  schools: platformDemoSchools.length,
}))
function platformStatusLabel(status) {
  if (status === 'active') return t.value.activeSubscription
  if (status === 'trial') return t.value.trialSubscription
  if (status === 'paused') return t.value.pausedSubscription
  return status === 'expired' ? (language.value === 'RU' ? 'Просрочен' : 'Beidzies') : (language.value === 'RU' ? 'Завершён' : 'Pabeigts')
}
function subscriptionPaymentLabel(state) {
  return state === 'paid' ? t.value.subscriptionPaid : (state === 'partial' ? t.value.subscriptionPartPaid : t.value.subscriptionUnpaid)
}
function platformDaysLeft(item) {
  if (!item?.paidThrough || item.paidThrough === '—') return null
  const today = new Date(); today.setHours(0, 0, 0, 0)
  const end = new Date(`${item.paidThrough}T00:00:00`)
  return Math.ceil((end - today) / 86400000)
}
function platformPaymentClass(item) {
  const days = platformDaysLeft(item)
  if (days === null) return 'no-period'
  if (days < 0) return 'expired'
  if (days <= 14) return 'expiring'
  return 'current'
}
function platformDaysLabel(item) {
  const days = platformDaysLeft(item)
  if (days === null) return '—'
  if (days < 0) return `${t.value.expiredAgo}: ${Math.abs(days)}`
  return `${days} ${t.value.daysShort}`
}
function addBillingMonths(dateValue, months) {
  if (!dateValue || !months) return dateValue || '—'
  const result = new Date(`${dateValue}T12:00:00`)
  result.setMonth(result.getMonth() + Number(months))
  return result.toISOString().slice(0, 10)
}
function openPlatformInstructor(item) {
  selectedPlatformSchool.value = null
  selectedPlatformInstructor.value = item
  platformSubscriptionForm.value = { plan: item.plan, status: item.status, paidAt: item.paidAt === '—' ? '' : item.paidAt, periodMonths: item.periodMonths || 1, paidAmount: item.paidAmount || 0, customPriceEnabled: item.customAmount !== null && item.customAmount !== undefined, customAmount: Number(item.customAmount ?? item.standardAmount ?? 0), note: '' }
  platformTerminationForm.value = { effectiveOn: item.terminationEffectiveOn || '', exportAccessUntil: item.exportAccessUntil || '', note: '' }
  platformSubscriptionSaved.value = false
  platformTerminationSaved.value = false
}
function openPlatformSchool(item) { selectedPlatformInstructor.value = null; selectedPlatformSchool.value = item }
function platformSchoolInstructors(school) { return platformDemoInstructors.filter((item) => item.schools.includes(school.name)) }
function normalizePlatformInstructor(item) {
  const months = Number(item.periodMonths || 0)
  const paidAmount = Number(item.paidAmount || 0)
  const agreedAmount = Number(item.agreedAmount ?? item.standardAmount ?? 0)
  const balance = Math.max(0, Math.round((agreedAmount - paidAmount) * 100) / 100)
  const paymentState = paidAmount <= 0 ? 'unpaid' : (balance > 0 ? 'partial' : 'paid')
  return { ...item, phone: item.phone || '', email: item.email || '', schools: Array.isArray(item.schools) ? item.schools : [], paidAt: item.paidAt || '—', paidThrough: item.graceUntil || item.paidThrough || '—', periodMonths: months, paidAmount, agreedAmount, balance, paymentState, monthly: months ? Math.round((agreedAmount / months) * 100) / 100 : 0 }
}
function normalizePlatformSchool(item) {
  return { ...item, city: item.city || '', phone: item.phone || '', email: item.email || '', widget: item.widget || 'compact', instructors: Number(item.instructors || 0) }
}
async function loadPlatformAdminDashboard() {
  platformAdminBusy.value = true
  platformAdminError.value = ''
  try {
    const dashboard = await repository.loadPlatformAdminDashboard()
    platformDemoSchools.splice(0, platformDemoSchools.length, ...(dashboard?.schools || []).map(normalizePlatformSchool))
    platformDemoInstructors.splice(0, platformDemoInstructors.length, ...(dashboard?.instructors || []).map(normalizePlatformInstructor))
    platformPaymentClaims.value = dashboard?.paymentClaims || []
    platformAuditLog.value = dashboard?.auditLog || []
    try {
      const prices = await repository.loadPlatformPlanPrices()
      if (prices?.length) platformPlanPrices.value = prices.map((item) => ({ ...item, totalAmount: Number(item.totalAmount) }))
    } catch (error) {
      console.warn('Platform plan prices are not installed yet', error)
    }
  } catch (error) {
    console.error('Platform admin load failed', error)
    platformAdminError.value = language.value === 'RU' ? 'Нет доступа администратора платформы или серверные функции ещё не установлены.' : 'Nav platformas administratora piekļuves vai servera funkcijas vēl nav instalētas.'
  } finally { platformAdminBusy.value = false }
}

function pricesForPlan(plan) {
  return platformPlanPrices.value.filter((item) => item.plan === plan).sort((a, b) => a.periodMonths - b.periodMonths)
}
const selectedStandardPrice = computed(() => Number(platformPlanPrices.value.find((item) => item.plan === platformSubscriptionForm.value.plan && item.periodMonths === Number(platformSubscriptionForm.value.periodMonths))?.totalAmount || 0))
const selectedAgreedPrice = computed(() => platformSubscriptionForm.value.customPriceEnabled ? Number(platformSubscriptionForm.value.customAmount || 0) : selectedStandardPrice.value)
const selectedPaymentBalance = computed(() => Math.max(0, Math.round((selectedAgreedPrice.value - Number(platformSubscriptionForm.value.paidAmount || 0)) * 100) / 100))
const selectedPaymentState = computed(() => Number(platformSubscriptionForm.value.paidAmount || 0) <= 0 ? 'unpaid' : (selectedPaymentBalance.value > 0 ? 'partial' : 'paid'))

function markPlatformSubscriptionPaid() {
  platformSubscriptionForm.value.paidAmount = selectedAgreedPrice.value
  platformSubscriptionForm.value.paidAt = new Date().toISOString().slice(0, 10)
  platformSubscriptionSaved.value = false
}

async function savePlatformPrices() {
  platformAdminBusy.value = true
  platformAdminError.value = ''
  platformPricesSaved.value = false
  try {
    const prices = await repository.savePlatformPlanPrices(platformPlanPrices.value.map(({ plan, periodMonths, totalAmount }) => ({ plan, periodMonths, totalAmount: Number(totalAmount) })))
    platformPlanPrices.value = prices.map((item) => ({ ...item, totalAmount: Number(item.totalAmount) }))
    await nextTick()
    platformPricesSaved.value = true
  } catch (error) {
    console.error('Platform plan prices save failed', error)
    platformAdminError.value = error.message || t.value.saveError
  } finally {
    platformAdminBusy.value = false
  }
}
async function savePlatformSubscription() {
  if (!selectedPlatformInstructor.value) return
  const item = selectedPlatformInstructor.value
  platformAdminBusy.value = true
  platformAdminError.value = ''
  try {
    await repository.savePlatformSubscription(item.id, platformSubscriptionForm.value)
    await loadPlatformAdminDashboard()
    selectedPlatformInstructor.value = platformDemoInstructors.find((entry) => entry.id === item.id) || null
    platformSubscriptionSaved.value = true
  } catch (error) {
    console.error('Platform subscription save failed', error)
    platformAdminError.value = t.value.saveError
  } finally { platformAdminBusy.value = false }
}

async function createPlatformSchool() {
  platformAdminBusy.value = true
  platformAdminError.value = ''
  platformSchoolCreated.value = false
  try {
    await repository.createPlatformSchool(platformSchoolForm.value)
    await loadPlatformAdminDashboard()
    platformSchoolCreated.value = true
    platformSchoolForm.value = { name: '', slug: '', adminEmail: '', registrationNumber: '', email: '', phone: '', websiteUrl: '' }
  } catch (error) {
    console.error('Platform school creation failed', error)
    const message = error.message || ''
    platformAdminError.value = message.includes('must register')
      ? t.value.schoolAdminMissing
      : message.includes('already exists') ? t.value.schoolSlugExists : (message || t.value.managementError)
  } finally {
    platformAdminBusy.value = false
  }
}

async function savePlatformTermination(clear = false) {
  const item = selectedPlatformInstructor.value
  if (!item || repository.mode === 'demo') return
  platformAdminBusy.value = true
  platformAdminError.value = ''
  platformTerminationSaved.value = false
  try {
    const form = platformTerminationForm.value
    await repository.managePlatformSubscriptionTermination(
      item.id,
      clear ? '' : form.effectiveOn,
      clear ? '' : form.exportAccessUntil,
      form.note,
    )
    await loadPlatformAdminDashboard()
    selectedPlatformInstructor.value = platformDemoInstructors.find((entry) => entry.id === item.id) || null
    if (clear) platformTerminationForm.value = { effectiveOn: '', exportAccessUntil: '', note: '' }
    platformTerminationSaved.value = true
  } catch (error) {
    console.error('Platform termination save failed', error)
    platformAdminError.value = error.message || t.value.saveError
  } finally {
    platformAdminBusy.value = false
  }
}
const timeSlots = computed(() => {
  const slots = []
  const step = Number(slotMinutes.value)
  for (let value = minutes(workStart.value); value <= minutes(workEnd.value); value += step) slots.push(clock(value))
  return slots
})
const scheduleBoundarySlots = Array.from({ length: 37 }, (_, index) => clock(6 * 60 + index * 30))
const visibleTimeSlots = computed(() => timeSlots.value)
const availableEndSlots = computed(() => scheduleBoundarySlots.filter((time) => minutes(time) >= minutes(workStart.value)))
const mainGridColumns = computed(() => `48px ${weekDays.value.map((_, index) => index === activeDayIndex.value ? 'minmax(210px,2.8fr)' : 'minmax(48px,.65fr)').join(' ')}`)
const weekRange = computed(() => `${weekDays.value[0].date.getDate()}. ${t.value.months[weekDays.value[0].date.getMonth()]} – ${weekDays.value[6].date.getDate()}. ${t.value.months[weekDays.value[6].date.getMonth()]} ${weekDays.value[6].date.getFullYear()}`)
const activeDayTitle = computed(() => `${t.value.weekdays[activeDay.value.date.getDay()]}, ${activeDay.value.date.getDate()}. ${t.value.months[activeDay.value.date.getMonth()]}`)
function lessonDateTitle(value) { const date = new Date(`${value}T12:00:00`); return `${t.value.weekdays[date.getDay()]}, ${date.getDate()}. ${t.value.months[date.getMonth()]} ${date.getFullYear()}` }
const datePickerWeekdays = computed(() => [1, 2, 3, 4, 5, 6, 0].map((day) => t.value.shortDays[day]))
const datePickerTitle = computed(() => new Intl.DateTimeFormat(t.value.locale, { month: 'long', year: 'numeric' }).format(datePickerMonth.value))
const datePickerDays = computed(() => {
  const first = new Date(datePickerMonth.value.getFullYear(), datePickerMonth.value.getMonth(), 1, 12)
  const start = addDays(first, -((first.getDay() + 6) % 7))
  return Array.from({ length: 42 }, (_, index) => {
    const date = addDays(start, index)
    return { iso: isoDate(date), number: date.getDate(), currentMonth: date.getMonth() === first.getMonth() }
  })
})

function vehicleMatchesFilters(vehicle) {
  const transmissionMatch = transmission.value === 'ALL' || vehicle.transmission === transmission.value
  const makeMatch = vehicleMake.value === 'ALL' || vehicle.name.trim().split(/\s+/)[0].toLocaleLowerCase() === vehicleMake.value.toLocaleLowerCase()
  return transmissionMatch && makeMatch
}
function visibleVehicles(instructor) { return instructor.vehicles.filter(vehicleMatchesFilters) }
const filteredInstructors = computed(() => publicInstructors.value.filter((item) => {
  const vehicleMatch = (transmission.value === 'ALL' && vehicleMake.value === 'ALL') || item.vehicles.some(vehicleMatchesFilters)
  const districtMatch = district.value === 'ALL' || item.meetingPoints.some((point) => point.includes(district.value))
  return vehicleMatch && districtMatch
}))
const vehicleMakes = computed(() => [...new Set(publicInstructors.value.flatMap((item) => item.vehicles.map((vehicle) => vehicle.name.trim().split(/\s+/)[0]).filter(Boolean)))].sort((a, b) => a.localeCompare(b)))
const widgetReturnUrl = query.get('return') || ''
const widgetCatalogUrl = computed(() => {
  const returnUrl = widgetReturnUrl || (document.referrer && /^https?:\/\//i.test(document.referrer) ? document.referrer : '')
  const params = new URLSearchParams({ layout: 'compact' })
  if (returnUrl) params.set('return', returnUrl)
  return `${window.location.origin}${window.location.pathname}?${params}#widget/${widgetSchoolSlug}/compact`
})
const widgetSettings = computed(() => widgetSchool.value?.settings || {})
const widgetTheme = computed(() => widgetSettings.value.theme || 'ikars')
const widgetShowPhotos = computed(() => !publicWidgetMode || widgetSettings.value.showPhotos !== false)
const widgetThemeStyle = computed(() => widgetTheme.value === 'custom' ? { '--widget-accent': widgetSettings.value.accentColor || '#0d827b' } : {})
const widgetReturnLabel = computed(() => widgetReturnUrl.includes('view=school-statistics') ? t.value.backToSchoolCabinet : t.value.backToSchoolSite)
const filteredStudents = computed(() => {
  const query = studentSearch.value.trim().toLocaleLowerCase(language.value === 'LV' ? 'lv-LV' : 'ru-RU')
  if (!query) return studentRecords.value
  return studentRecords.value.filter((student) => `${student.firstName} ${student.lastName} ${student.phone}`.toLocaleLowerCase().includes(query))
})
const selectedStudentLessons = computed(() => {
  if (!studentForm.value) return []
  const today = isoDate(new Date())
  return schedule.value
    .filter((lesson) => lesson.studentId === studentForm.value.id && lesson.date <= today)
    .sort((a, b) => `${b.date}T${b.time}`.localeCompare(`${a.date}T${a.time}`))
})
const selectedStudentFinance = computed(() => {
  const charged = selectedStudentLessons.value
    .filter((lesson) => lesson.chargeable && ['completed', 'no_show'].includes(lesson.status))
    .reduce((total, lesson) => total + Number(lesson.price || 0), 0)
  const paid = Number(studentForm.value?.paid || 0)
  return { charged, paid, debt: Math.max(charged - paid, 0), credit: Math.max(paid - charged, 0) }
})
const backupReminderDue = computed(() => {
  if (!lastCalendarExport.value) return true
  return Date.now() - new Date(lastCalendarExport.value).getTime() >= BACKUP_REMINDER_DAYS * 86400000
})
const showBackupReminder = computed(() => backupReminderDue.value && (!backupReminderSnoozedUntil.value || Date.now() >= new Date(backupReminderSnoozedUntil.value).getTime()))
const lessonStudentSuggestions = computed(() => {
  const query = lessonForm.value?.student?.trim().toLocaleLowerCase(language.value === 'LV' ? 'lv-LV' : 'ru-RU') || ''
  if (!lessonDialog.value || !query) return []
  const selected = studentRecords.value.find((student) => student.id === lessonForm.value.studentId)
  if (selected && `${selected.firstName} ${selected.lastName}`.toLocaleLowerCase(language.value === 'LV' ? 'lv-LV' : 'ru-RU') === query) return []
  return studentRecords.value.filter((student) => {
    if (student.status !== 'active') return false
    const first = student.firstName.toLocaleLowerCase(language.value === 'LV' ? 'lv-LV' : 'ru-RU')
    const last = student.lastName.toLocaleLowerCase(language.value === 'LV' ? 'lv-LV' : 'ru-RU')
    const full = `${first} ${last}`
    return first.startsWith(query) || last.startsWith(query) || full.startsWith(query) || student.phone?.startsWith(query)
  }).slice(0, 6)
})

function minutes(value) { const [hours, mins] = value.split(':').map(Number); return hours * 60 + mins }
function clock(value) { const safe = Math.min(value, 24 * 60); return `${String(Math.floor(safe / 60)).padStart(2, '0')}:${String(safe % 60).padStart(2, '0')}` }
function lessonAt(time) { return schedule.value.find((lesson) => lesson.date === activeDay.value.iso && lesson.time === time) }
function lessonFor(dayIso, time) { return schedule.value.find((lesson) => lesson.status !== 'cancelled' && lesson.date === dayIso && lesson.time === time) }
function blockFor(dayIso, time) { return calendarBlocks.value.find((block) => block.date === dayIso && minutes(time) < minutes(block.end) && minutes(time) + Number(slotMinutes.value) > minutes(block.time)) }
function slotIsFree(dayIso, time) { return !blockFor(dayIso, time) && !schedule.value.some((lesson) => lesson.status !== 'cancelled' && lesson.date === dayIso && minutes(time) < minutes(lesson.end) && minutes(time) + Number(slotMinutes.value) > minutes(lesson.time)) }
const activeDayBlocked = computed(() => visibleTimeSlots.value.length > 0 && visibleTimeSlots.value.every((time) => Boolean(blockFor(activeDay.value.iso, time)) || Boolean(lessonFor(activeDay.value.iso, time))))
async function toggleSlotBlock(dayIso, time) {
  if (billingReadOnly.value) return
  const existing = blockFor(dayIso, time)
  if (existing) await repository.deleteCalendarBlock(existing.id)
  else await repository.saveCalendarBlock({ id: crypto.randomUUID(), date: dayIso, time, end: clock(minutes(time) + Number(slotMinutes.value)), reason: 'manual' })
  await loadWorkspace()
}
async function toggleActiveDayBlock() {
  if (billingReadOnly.value) return
  const existing = calendarBlocks.value.filter((block) => block.date === activeDay.value.iso)
  if (existing.length) await Promise.all(existing.map((block) => repository.deleteCalendarBlock(block.id)))
  else {
    const freeSlots = visibleTimeSlots.value.filter((time) => !lessonFor(activeDay.value.iso, time))
    await Promise.all(freeSlots.map((time) => repository.saveCalendarBlock({ id: crypto.randomUUID(), date: activeDay.value.iso, time, end: clock(minutes(time) + Number(slotMinutes.value)), reason: 'day' })))
  }
  await loadWorkspace()
}
function dayEnabled(index) { return index < 5 || (index === 5 ? saturdayEnabled.value : sundayEnabled.value) }
function normalizeWorkRange() { if (minutes(workEnd.value) < minutes(workStart.value)) workEnd.value = workStart.value }
function changeWeek(delta) { weekOffset.value += delta; activeDayIndex.value = 0 }
function resetWeek() {
  if (repository.mode === 'demo') { weekOffset.value = 0; activeDayIndex.value = 0; return }
  focusCalendarDate(isoDate(new Date()))
  centerActiveCalendarDay()
}
async function centerActiveCalendarDay() {
  await nextTick()
  window.requestAnimationFrame(() => {
    const container = calendarScroll.value
    const activeHeader = container?.querySelector('.grid-day.active')
    if (!container || !activeHeader) return
    const stickyTimeWidth = 48
    const visibleWidth = Math.max(container.clientWidth - stickyTimeWidth, 0)
    const target = activeHeader.offsetLeft - stickyTimeWidth - Math.max((visibleWidth - activeHeader.offsetWidth) / 2, 0)
    container.scrollTo({ left: Math.max(target, 0), behavior: 'smooth' })
  })
}
function focusCalendarDate(value) {
  const target = new Date(`${value}T12:00:00`)
  const daysFromMonday = Math.round((target - calendarAnchorMonday) / 86400000)
  weekOffset.value = Math.floor(daysFromMonday / 7)
  activeDayIndex.value = ((daysFromMonday % 7) + 7) % 7
}
function openDatePicker() {
  const selected = new Date(`${lessonForm.value.date}T12:00:00`)
  datePickerMonth.value = new Date(selected.getFullYear(), selected.getMonth(), 1, 12)
  datePickerOpen.value = true
}
function changeDatePickerMonth(delta) { datePickerMonth.value = new Date(datePickerMonth.value.getFullYear(), datePickerMonth.value.getMonth() + delta, 1, 12) }
function selectLessonDate(day) { lessonForm.value.date = day.iso; datePickerOpen.value = false }
function openLesson(time, existing = null) {
  if (billingReadOnly.value) { showSaveNotice(t.value.billingReadOnlyNotice); return }
  lessonError.value = ''
  datePickerOpen.value = false
  if (!currentInstructor.value.vehicles.length || !currentInstructor.value.meetingPoints.length) {
    openAccount()
    accountMessage.value = t.value.noVehicle
    return
  }
  if (existing) {
    const vehicle = currentInstructor.value.vehicles.find((item) => existing.vehicle.startsWith(item.transmission) && existing.vehicle.includes(item.name.split(' ').at(-1))) || currentInstructor.value.vehicles[0]
    lessonForm.value = { id: existing.id, studentId: existing.studentId || null, originalStudentId: existing.studentId || null, date: existing.date, time: existing.time, duration: minutes(existing.end) - minutes(existing.time), student: existing.student, vehicleId: existing.vehicleId || vehicle.id, price: existing.price, meetingPointId: existing.meetingPointId || currentInstructor.value.meetingPoints[0].id, point: existing.point, status: existing.status || 'planned', chargeable: existing.chargeable || false, paymentStatus: existing.paymentStatus || 'unpaid', paymentMethod: existing.paymentMethod || 'cash', note: existing.note || '' }
  } else {
    const vehicle = currentInstructor.value.vehicles[0]
    lessonForm.value = { id: null, studentId: null, originalStudentId: null, date: activeDay.value.iso, time, duration: Number(slotMinutes.value), student: '', vehicleId: vehicle.id, price: vehicle.price, meetingPointId: currentInstructor.value.meetingPoints[0].id, point: currentInstructor.value.meetingPoints[0].label || currentInstructor.value.meetingPoints[0], status: 'planned', chargeable: false, paymentStatus: 'unpaid', paymentMethod: 'cash', note: '' }
  }
  lessonDialog.value = true
}
function handleLessonStudentInput() {
  if (lessonForm.value.originalStudentId) return
  const value = lessonForm.value.student.trim().toLocaleLowerCase(language.value === 'LV' ? 'lv-LV' : 'ru-RU')
  const exact = studentRecords.value.find((student) => student.status === 'active' && `${student.firstName} ${student.lastName}`.toLocaleLowerCase(language.value === 'LV' ? 'lv-LV' : 'ru-RU') === value)
  lessonForm.value.studentId = exact?.id || null
}
function selectLessonStudent(student) {
  lessonForm.value.student = `${student.firstName} ${student.lastName}`
  lessonForm.value.studentId = student.id
  lessonForm.value.vehicleId = student.vehicleId || lessonForm.value.vehicleId
  if (student.price) lessonForm.value.price = student.price
}
function selectVehicle() {
  const vehicle = currentInstructor.value.vehicles.find((item) => item.id === lessonForm.value.vehicleId)
  if (vehicle) lessonForm.value.price = vehicle.price
}
function changeLessonStatus() {
  if (lessonForm.value.status === 'completed' || lessonForm.value.status === 'no_show') lessonForm.value.chargeable = true
  if (lessonForm.value.status === 'cancelled' || lessonForm.value.status === 'planned') lessonForm.value.chargeable = false
}
function showSaveNotice(message) {
  saveNotice.value = message
  window.clearTimeout(saveNoticeTimer)
  saveNoticeTimer = window.setTimeout(() => { saveNotice.value = '' }, 4500)
}
async function saveLesson() {
  if (billingReadOnly.value) { lessonError.value = t.value.billingReadOnlyNotice; return }
  lessonError.value = ''
  if (!lessonForm.value.student.trim()) { lessonError.value = t.value.required; return }
  const start = minutes(lessonForm.value.time)
  const end = start + Number(lessonForm.value.duration)
  const conflict = schedule.value.some((lesson) => lesson.status !== 'cancelled' && lesson.id !== lessonForm.value.id && lesson.date === lessonForm.value.date && start < minutes(lesson.end) && end > minutes(lesson.time))
  const blocked = calendarBlocks.value.some((block) => block.date === lessonForm.value.date && start < minutes(block.end) && end > minutes(block.time))
  if (conflict || blocked) { lessonError.value = t.value.conflict; return }
  const vehicle = currentInstructor.value.vehicles.find((item) => item.id === lessonForm.value.vehicleId)
  const meetingPoint = currentInstructor.value.meetingPoints.find((item) => item.label === lessonForm.value.point) || currentInstructor.value.meetingPoints.find((item) => item.id === lessonForm.value.meetingPointId)
  if (lessonForm.value.paymentStatus === 'paid' && lessonForm.value.paymentMethod === 'advance') {
    const student = studentRecords.value.find((item) => item.id === lessonForm.value.studentId)
    const previousLesson = schedule.value.find((item) => item.id === lessonForm.value.id)
    const reusableAllocation = previousLesson?.paymentMethod === 'advance' ? Number(previousLesson.price || 0) : 0
    if (Number(student?.advanceBalance || 0) + reusableAllocation < Number(lessonForm.value.price || 0)) {
      lessonError.value = t.value.insufficientAdvance
      return
    }
  }
  const saved = { id: lessonForm.value.id, studentId: lessonForm.value.studentId, date: lessonForm.value.date, time: lessonForm.value.time, end: clock(end), student: lessonForm.value.student.trim(), vehicle: `${vehicle.transmission} · ${vehicle.name.split(' ').at(-1)}`, vehicleId: vehicle.id, price: Number(lessonForm.value.price), point: meetingPoint?.label || '', meetingPointId: meetingPoint?.id || null, status: lessonForm.value.status, chargeable: lessonForm.value.chargeable, paymentStatus: lessonForm.value.paymentStatus, paymentMethod: lessonForm.value.paymentMethod, note: lessonForm.value.note.trim() }
  try {
    const persistedLesson = await repository.saveLesson(saved)
    await loadWorkspace()
    focusCalendarDate(persistedLesson?.date || saved.date)
    lessonDialog.value = false
    showSaveNotice(t.value.lessonSaved)
  } catch (error) {
    lessonError.value = (error.message || '').includes('INSUFFICIENT_STUDENT_ADVANCE') ? t.value.insufficientAdvance : t.value.saveError
  }
}
function excelCell(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}
function exportCalendarXls() {
  if (!billingExportAllowed.value) { showSaveNotice(t.value.exportLocked); return }
  if (!exportDateFrom.value || !exportDateTo.value || exportDateFrom.value > exportDateTo.value) { showSaveNotice(t.value.exportRangeError); return }
  const headers = language.value === 'LV'
    ? ['Datums', 'Laiks', 'Audzēknis', 'Statuss', 'Automobilis', 'Tikšanās vieta', 'Cena', 'Apmaksa', 'Apmaksas veids', 'Piezīme']
    : ['Дата', 'Время', 'Ученик', 'Статус', 'Автомобиль', 'Место встречи', 'Цена', 'Оплата', 'Способ оплаты', 'Примечание']
  const exportedLessons = schedule.value.filter((lesson) => lesson.date >= exportDateFrom.value && lesson.date <= exportDateTo.value).sort((a, b) => `${a.date}T${a.time}`.localeCompare(`${b.date}T${b.time}`))
  const rows = exportedLessons.map((lesson) => [
    lesson.date, `${lesson.time}–${lesson.end}`, lesson.student,
    t.value[lesson.status === 'no_show' ? 'noShow' : lesson.status] || lesson.status,
    lesson.vehicle, lesson.point, Number(lesson.price || 0),
    lesson.paymentStatus === 'paid' ? t.value.paidStatus : t.value.unpaid,
    lesson.paymentStatus === 'paid' ? (t.value[lesson.paymentMethod === 'school' ? 'schoolPayment' : lesson.paymentMethod] || lesson.paymentMethod) : '—',
    lesson.note || '',
  ])
  const dates = []
  for (let date = new Date(`${exportDateFrom.value}T12:00:00`), endDate = new Date(`${exportDateTo.value}T12:00:00`); date <= endDate; date.setDate(date.getDate() + 1)) dates.push(isoDate(date))
  const xmlRow = (row, style = '') => `<Row>${row.map((cell, index) => `<Cell${style ? ` ss:StyleID="${style}"` : ''}><Data ss:Type="${index === 6 && !style ? 'Number' : 'String'}">${excelCell(cell)}</Data></Cell>`).join('')}</Row>`
  const calendarHeader = [language.value === 'LV' ? 'Laiks' : 'Время', ...dates.map((date) => { const value = new Date(`${date}T12:00:00`); return `${t.value.shortDays[value.getDay()]} ${value.getDate()}.${String(value.getMonth() + 1).padStart(2, '0')}` })]
  const calendarRows = visibleTimeSlots.value.map((time) => [time, ...dates.map((date) => {
    const lesson = exportedLessons.find((item) => item.date === date && item.time === time)
    if (!lesson) return ''
    const status = t.value[lesson.status === 'no_show' ? 'noShow' : lesson.status] || lesson.status
    const payment = lesson.paymentStatus === 'paid' ? t.value.paidStatus : t.value.unpaid
    return `${lesson.student}\n${status} · ${payment}\n€${lesson.price} · ${lesson.vehicle}`
  })])
  const workbook = `<?xml version="1.0" encoding="UTF-8"?><?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Styles><Style ss:ID="Default"><Alignment ss:Vertical="Center"/><Font ss:FontName="Arial" ss:Size="10"/></Style><Style ss:ID="Header"><Font ss:FontName="Arial" ss:Size="10" ss:Bold="1"/><Interior ss:Color="#DDECE9" ss:Pattern="Solid"/><Alignment ss:WrapText="1"/></Style><Style ss:ID="Calendar"><Alignment ss:Vertical="Top" ss:WrapText="1"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D7E5E3"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1" ss:Color="#D7E5E3"/></Borders></Style></Styles>
<Worksheet ss:Name="${language.value === 'LV' ? 'Detalizēti' : 'Подробно'}"><Table><Column ss:Width="78"/><Column ss:Width="72"/><Column ss:Width="125"/><Column ss:Width="90"/><Column ss:Width="110"/><Column ss:Width="170"/><Column ss:Width="55"/><Column ss:Width="85"/><Column ss:Width="120"/><Column ss:Width="190"/>${xmlRow(headers, 'Header')}${rows.map((row) => xmlRow(row)).join('')}</Table><WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel"><FreezePanes/><FrozenNoSplit/><SplitHorizontal>1</SplitHorizontal><TopRowBottomPane>1</TopRowBottomPane></WorksheetOptions></Worksheet>
<Worksheet ss:Name="${language.value === 'LV' ? 'Kalendārs' : 'Календарь'}"><Table><Column ss:Width="55"/>${dates.map(() => '<Column ss:Width="125"/>').join('')}${xmlRow(calendarHeader, 'Header')}${calendarRows.map((row) => xmlRow(row, 'Calendar')).join('')}</Table><WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel"><FreezePanes/><FrozenNoSplit/><SplitHorizontal>1</SplitHorizontal><SplitVertical>1</SplitVertical><TopRowBottomPane>1</TopRowBottomPane><LeftColumnRightPane>1</LeftColumnRightPane></WorksheetOptions></Worksheet></Workbook>`
  const blob = new Blob([workbook], { type: 'application/vnd.ms-excel;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `IKARS-calendar-${new Date().toISOString().slice(0, 10)}.xls`
  document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url)
  const exportedAt = new Date().toISOString()
  lastCalendarExport.value = exportedAt
  backupReminderSnoozedUntil.value = ''
  localStorage.setItem(BACKUP_STORAGE_KEY, exportedAt)
  localStorage.removeItem(BACKUP_SNOOZE_KEY)
  showSaveNotice(t.value.exportReady)
}
function snoozeBackupReminder() {
  const until = new Date(Date.now() + 7 * 86400000).toISOString()
  backupReminderSnoozedUntil.value = until
  localStorage.setItem(BACKUP_SNOOZE_KEY, until)
}
function formatAvailability(slot) {
  const date = new Date(`${slot.date}T12:00:00`)
  return `${t.value.weekdays[date.getDay()]}, ${date.getDate()}. ${t.value.months[date.getMonth()]} · ${slot.time}`
}
function instructorDaySlots(instructor, date) { return instructor.availability.filter((slot) => slot.date === isoDate(date)) }
function instructorSlotIsFree(instructor, date, time) { return instructor.availability.some((slot) => slot.date === isoDate(date) && slot.time === time) }
async function centerPublicCalendarToday() {
  await nextTick()
  window.requestAnimationFrame(() => {
    const container = publicCalendarScroll.value
    if (!container) return
    const todayIndex = (new Date().getDay() + 6) % 7
    const todayHeader = container.querySelectorAll('.grid-day')[todayIndex]
    if (!todayHeader) return
    const timeColumnWidth = 48
    const visibleWidth = Math.max(container.clientWidth - timeColumnWidth, 0)
    const target = todayHeader.offsetLeft - timeColumnWidth - Math.max((visibleWidth - todayHeader.offsetWidth) / 2, 0)
    container.scrollTo({ left: Math.max(target, 0), behavior: 'auto' })
  })
}
function openAvailability(instructor) { availabilityInstructor.value = instructor; weekOffset.value = 0; availabilityDialog.value = true; centerPublicCalendarToday(); publicEvent('instructor_profile_view', instructor.id, { action: 'availability_calendar' }) }
function publicEvent(type, instructorId = null, metadata = {}, activeSeconds = null) {
  if (!publicDirectoryMode) return
  const width = window.innerWidth
  void repository.recordPublicEvent({ type, sessionId: publicSessionId, source: publicWidgetMode ? 'school_widget' : 'catalog', schoolSlug: publicWidgetMode ? widgetSchoolSlug : null, instructorId, activeSeconds, language: language.value.toLowerCase(), deviceType: width < 768 ? 'mobile' : (width < 1100 ? 'tablet' : 'desktop'), metadata }).catch(() => {})
}
function openProfile(instructor) { selectedInstructor.value = instructor; analytics.value.profileViews += 1; publicEvent('instructor_profile_view', instructor.id); persistAnalytics() }
function openPhoto(instructor) { enlargedPhoto.value = instructor }
function closePhoto() { enlargedPhoto.value = null }
function handleGlobalKeydown(event) { if (event.key === 'Escape') closePhoto() }
async function openStudent(student) {
  studentForm.value = { ...student }
  studentAdvanceForm.value = { amount: '', method: 'cash', paidAt: new Date().toISOString().slice(0, 10), note: '' }
  studentAdvanceMessage.value = ''
  studentLessonsVisible.value = false
  studentScheduleLink.value = ''
  studentScheduleMessage.value = ''
  studentScheduleAccessExists.value = false
  studentScheduleShowFullHistory.value = true
  studentDialog.value = true
  if (repository.mode === 'demo') return
  try {
    const settings = await repository.loadStudentScheduleSettings(student.id)
    studentScheduleAccessExists.value = Boolean(settings.enabled)
    studentScheduleShowFullHistory.value = settings.showFullHistory !== false
  } catch (error) { console.error('Student schedule settings load failed', JSON.stringify(error)) }
}

async function recordStudentAdvance() {
  if (!studentForm.value?.id || Number(studentAdvanceForm.value.amount) <= 0) return
  studentAdvanceBusy.value = true; studentAdvanceMessage.value = ''
  try {
    const studentId = studentForm.value.id
    await repository.recordStudentAdvance(studentId, studentAdvanceForm.value)
    await loadWorkspace()
    studentForm.value = { ...studentRecords.value.find((item) => item.id === studentId) }
    studentAdvanceForm.value = { amount: '', method: 'cash', paidAt: new Date().toISOString().slice(0, 10), note: '' }
    studentAdvanceMessage.value = t.value.advanceSaved
    showSaveNotice(t.value.advanceSaved)
  } catch (error) {
    console.error('Advance payment save failed', error)
    studentAdvanceMessage.value = t.value.saveError
  } finally { studentAdvanceBusy.value = false }
}

async function voidStudentAdvance(payment) {
  const reason = window.prompt(t.value.voidReason)
  if (!reason?.trim()) return
  studentAdvanceBusy.value = true; studentAdvanceMessage.value = ''
  try {
    const studentId = studentForm.value.id
    await repository.voidStudentAdvancePayment(payment.id, reason.trim())
    await loadWorkspace()
    studentForm.value = { ...studentRecords.value.find((item) => item.id === studentId) }
    studentAdvanceMessage.value = t.value.saved
    showSaveNotice(t.value.saved)
  } catch (error) {
    console.error('Advance payment void failed', error)
    studentAdvanceMessage.value = (error.message || '').includes('ADVANCE_PAYMENT_ALREADY_ALLOCATED')
      ? (language.value === 'RU' ? 'Сначала отмените списание аванса с занятий.' : 'Vispirms atceliet avansa norakstīšanu no nodarbībām.')
      : t.value.saveError
  } finally { studentAdvanceBusy.value = false }
}
const studentUpcomingLessons = computed(() => (studentSchedule.value?.lessons || []).filter((lesson) => new Date(lesson.endsAt) >= new Date()))
const studentPastScheduleLessons = computed(() => (studentSchedule.value?.lessons || []).filter((lesson) => new Date(lesson.endsAt) < new Date()).reverse())

async function createPersonalStudentLink() {
  if (!studentForm.value?.id) return
  studentScheduleBusy.value = true; studentScheduleMessage.value = ''
  try {
    const result = await repository.createStudentScheduleLink(studentForm.value.id)
    await repository.saveStudentScheduleVisibility(studentForm.value.id, studentScheduleShowFullHistory.value)
    studentScheduleAccessExists.value = true
    studentScheduleLink.value = `${window.location.origin}${window.location.pathname}#student/${result.token}`
    studentScheduleMessage.value = t.value.studentLinkCreated
  } catch (error) {
    studentScheduleMessage.value = (error.message || '').includes('STUDENT_SCHEDULE_REQUIRES_BASIC') ? t.value.studentScheduleProOnly : t.value.saveError
  } finally { studentScheduleBusy.value = false }
}

async function copyPersonalStudentLink() {
  if (!studentScheduleLink.value) return
  await navigator.clipboard.writeText(studentScheduleLink.value)
  studentScheduleMessage.value = t.value.studentLinkCopied
}

async function revokePersonalStudentLink() {
  if (!studentForm.value?.id) return
  studentScheduleBusy.value = true
  try {
    await repository.revokeStudentScheduleLink(studentForm.value.id)
    studentScheduleAccessExists.value = false
    studentScheduleLink.value = ''
    studentScheduleMessage.value = t.value.studentLinkRevoked
  } catch { studentScheduleMessage.value = t.value.saveError }
  finally { studentScheduleBusy.value = false }
}

async function saveStudentScheduleVisibility() {
  if (!studentForm.value?.id || !studentScheduleAccessExists.value) return
  studentScheduleBusy.value = true; studentScheduleMessage.value = ''
  try {
    await repository.saveStudentScheduleVisibility(studentForm.value.id, studentScheduleShowFullHistory.value)
    studentScheduleMessage.value = t.value.studentVisibilitySaved
  } catch { studentScheduleMessage.value = t.value.saveError }
  finally { studentScheduleBusy.value = false }
}
function openStudentLesson(lesson) {
  studentDialog.value = false
  focusCalendarDate(lesson.date)
  openLesson(lesson.time, lesson)
}
function openNewStudent() {
  if (billingReadOnly.value) { showSaveNotice(t.value.billingReadOnlyNotice); return }
  const vehicle = currentInstructor.value.vehicles[0]
  if (!vehicle) { openAccount(); accountMessage.value = t.value.noVehicle; return }
  studentForm.value = { id: null, firstName: '', lastName: '', phone: '', email: '', school: '', vehicleId: vehicle.id, transmission: vehicle.transmission, price: vehicle.price, paid: 0, lessons: 0, status: 'active', notes: '' }
  studentDialog.value = true
}
async function saveStudent() {
  if (billingReadOnly.value) { authError.value = t.value.billingReadOnlyNotice; return }
  try {
    await repository.saveStudent(studentForm.value)
    await loadWorkspace()
    studentDialog.value = false
  } catch {
    authError.value = t.value.saveError
  }
}
function trackStudentCall(student) { window.location.href = `tel:${student.phone}` }
async function reportBillingPayment() {
  if (!billingDemoState && repository.mode !== 'demo') {
    try {
      await repository.submitSubscriptionPaymentClaim()
      billingPaymentReported.value = true
    } catch (error) {
      console.error('Subscription payment claim failed', error)
      showSaveNotice(t.value.saveError)
    }
    return
  }
  billingPaymentReported.value = true
  if (!platformPaymentClaims.value.some((item) => item.status === 'pending')) {
    platformPaymentClaims.value.unshift({ id: crypto.randomUUID(), instructor: `${currentInstructor.value.firstName || ''} ${currentInstructor.value.lastName || ''}`.trim() || 'Demo instructor', createdAt: new Date().toLocaleString(t.value.locale), status: 'pending' })
    localStorage.setItem(PAYMENT_CLAIMS_STORAGE_KEY, JSON.stringify(platformPaymentClaims.value))
  }
}
async function dismissBillingReminder() {
  if (billingDemoState === '7') { billingReminderDismissed.value = true; return }
  if (effectiveBillingState.value === '7' && billingNotification.value?.id) {
    try {
      await repository.dismissSubscriptionNotification(billingNotification.value.id)
      billingReminderDismissed.value = true
    } catch (error) { console.error('Subscription reminder dismissal failed', error) }
  }
}
async function resolvePaymentClaim(claim, status) {
  platformAdminBusy.value = true
  platformAdminError.value = ''
  try {
    await repository.resolvePlatformPaymentClaim(claim.id, status)
    await loadPlatformAdminDashboard()
  } catch (error) {
    console.error('Payment claim resolution failed', error)
    platformAdminError.value = t.value.saveError
  } finally { platformAdminBusy.value = false }
}
async function extendPlatformGrace(days) {
  if (!selectedPlatformInstructor.value) return
  const item = selectedPlatformInstructor.value
  platformAdminBusy.value = true
  platformAdminError.value = ''
  try {
    await repository.grantPlatformSubscriptionGrace(item.id, days, platformSubscriptionForm.value.note)
    await loadPlatformAdminDashboard()
    selectedPlatformInstructor.value = platformDemoInstructors.find((entry) => entry.id === item.id) || null
  } catch (error) {
    console.error('Grace update failed', error)
    platformAdminError.value = t.value.saveError
  } finally { platformAdminBusy.value = false }
}
function trackCall(instructor) { analytics.value.phoneClicks += 1; publicEvent('phone_click', instructor.id); persistAnalytics(); window.location.href = `tel:${instructor.phone}` }
function openPublicDirectory() { window.open(`${window.location.origin}${window.location.pathname}?view=directory`, '_blank', 'noopener') }
function openInstructorCabinet() { window.location.href = window.location.pathname }
function persistAnalytics() { void repository.saveAnalytics(analytics.value) }
function setVisibleActivity() {
  if (document.visibilityState === 'visible') activeStartedAt = Date.now()
  else if (activeStartedAt) { const elapsed = Math.round((Date.now() - activeStartedAt) / 1000); analytics.value.activeSeconds += elapsed; if (publicDirectoryMode) publicActiveSeconds += elapsed; activeStartedAt = 0; persistAnalytics() }
}

function reportWidgetHeight() {
  if (!publicWidgetMode || window.parent === window) return
  nextTick(() => {
    const widgetPage = document.querySelector('.widget-page')
    const height = Math.ceil(widgetPage?.getBoundingClientRect().height || document.body.scrollHeight)
    window.parent.postMessage({ type: 'ikars-widget-height', layout: widgetLayout.value, height }, '*')
  })
}

async function loadWorkspace() {
  const workspace = await repository.loadWorkspace()
  if (workspace.instructor) currentInstructor.value = workspace.instructor
  studentRecords.value = workspace.students
  schedule.value = workspace.lessons
  calendarBlocks.value = workspace.calendarBlocks || []
  if (workspace.availabilitySettings) {
    const settings = workspace.availabilitySettings
    workStart.value = settings.workStart
    workEnd.value = settings.workEnd
    slotMinutes.value = settings.slotMinutes
    saturdayEnabled.value = settings.saturdayEnabled
    sundayEnabled.value = settings.sundayEnabled
    freeColorMode.value = settings.freeColorMode
    busyColorMode.value = settings.busyColorMode
  }
  if (workspace.analytics) analytics.value = { ...analytics.value, ...workspace.analytics }
  schoolInvitations.value = workspace.schoolInvitations || []
  if (repository.mode !== 'demo') {
    try {
      subscriptionAccess.value = await repository.loadMySubscriptionAccess()
      billingNotification.value = subscriptionAccess.value?.notification || null
      billingPaymentReported.value = subscriptionAccess.value?.paymentClaimPending === true
    } catch (error) { console.error('Subscription access load failed', error) }
  }
}

async function respondToSchoolInvitation(invitation, response) {
  accountBusy.value = true; accountMessage.value = ''
  try {
    await repository.respondToSchoolInvitation(invitation.linkId, response)
    await loadWorkspace()
    accountMessage.value = response === 'accept' ? t.value.invitationAccepted : t.value.invitationDeclined
  } catch (error) {
    console.error('School invitation response failed', error)
    accountMessage.value = t.value.saveError
  } finally { accountBusy.value = false }
}

async function saveCalendarPreferences() {
  accountBusy.value = true; accountMessage.value = ''
  try {
    await repository.saveAvailabilitySettings({
      workStart: workStart.value,
      workEnd: workEnd.value,
      slotMinutes: slotMinutes.value,
      saturdayEnabled: saturdayEnabled.value,
      sundayEnabled: sundayEnabled.value,
      freeColorMode: freeColorMode.value,
      busyColorMode: busyColorMode.value,
    })
    accountMessage.value = t.value.saved
  } catch { accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}

function openAccount() {
  const instructor = currentInstructor.value
  profileForm.value = { firstName: instructor.firstName || '', lastName: instructor.lastName || '', phone: instructor.phone || '', photoUrl: instructor.photoUrl || '', languages: [...(instructor.languages || ['lv'])], categories: [...(instructor.categories || ['B'])], isPublic: Boolean(instructor.isPublic), publicPhone: instructor.publicPhone !== false, vehicles: instructor.vehicles, meetingPoints: instructor.meetingPoints }
  vehicleForm.value = { id: null, make: '', model: '', year: new Date().getFullYear(), transmission: 'M', price: 35, weekendPrice: '', registrationNumber: '', isActive: true }
  meetingPointForm.value = { id: null, city: 'Rīga', district: '', name: '', directions: '', surcharge: 0, isActive: true }
  accountMessage.value = ''
  accountDialog.value = true
}

async function prepareProfilePhoto(event) {
  const file = event.target.files?.[0]
  event.target.value = ''
  if (!file) return
  if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type) || file.size > 3 * 1024 * 1024) { accountMessage.value = t.value.photoInvalid; return }
  accountBusy.value = true; accountMessage.value = ''
  try {
    const image = await createImageBitmap(file)
    const sideWidth = Math.min(image.width, image.height * 4 / 5)
    const sideHeight = Math.min(image.height, image.width * 5 / 4)
    const sx = (image.width - sideWidth) / 2
    const sy = (image.height - sideHeight) / 2
    const canvas = document.createElement('canvas')
    canvas.width = 640; canvas.height = 800
    canvas.getContext('2d').drawImage(image, sx, sy, sideWidth, sideHeight, 0, 0, 640, 800)
    image.close()
    const photo = await new Promise((resolve) => canvas.toBlob(resolve, 'image/webp', .86))
    if (!photo) throw new Error('Photo conversion failed')
    const photoUrl = await repository.uploadInstructorPhoto(photo)
    currentInstructor.value.photoUrl = photoUrl
    profileForm.value.photoUrl = photoUrl
    accountMessage.value = t.value.photoSaved
  } catch (error) { console.error('Photo upload failed', error); accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}

async function deleteProfilePhoto() {
  if (!window.confirm(t.value.confirmDeletePhoto)) return
  accountBusy.value = true; accountMessage.value = ''
  try {
    await repository.deleteInstructorPhoto()
    currentInstructor.value.photoUrl = ''
    profileForm.value.photoUrl = ''
    accountMessage.value = t.value.photoDeleted
  } catch (error) { console.error('Photo deletion failed', error); accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}

function editVehicle(vehicle) { vehicleForm.value = { ...vehicle } }
function resetVehicleForm() { vehicleForm.value = { id: null, make: '', model: '', year: new Date().getFullYear(), transmission: 'M', price: 35, weekendPrice: '', registrationNumber: '', isActive: true } }
function editMeetingPoint(point) { meetingPointForm.value = { ...point } }
async function selectPublicMeetingPoint(point) {
  accountBusy.value = true; accountMessage.value = ''
  try {
    await repository.selectPublicMeetingPoint(point.id)
    currentInstructor.value.meetingPoints.forEach((item) => { item.showInWidget = item.id === point.id })
    profileForm.value.meetingPoints = currentInstructor.value.meetingPoints
    await loadWorkspace(); openAccount(); accountMessage.value = t.value.saved
  }
  catch (error) { console.error('Public meeting point selection failed', error); accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}
async function archiveMeetingPoint(point) {
  if (!window.confirm(t.value.confirmDeleteLocation)) return
  accountBusy.value = true; accountMessage.value = ''
  try {
    await repository.archiveMeetingPoint(point.id)
    currentInstructor.value.meetingPoints = currentInstructor.value.meetingPoints.filter((item) => item.id !== point.id)
    profileForm.value.meetingPoints = currentInstructor.value.meetingPoints
    await loadWorkspace(); openAccount(); accountMessage.value = t.value.saved
  }
  catch (error) { console.error('Meeting point archive failed', error); accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}

async function saveProfileSettings() {
  accountBusy.value = true; accountMessage.value = ''
  if (!profileForm.value.languages.length || !profileForm.value.categories.length) { accountMessage.value = t.value.chooseLanguageCategory; accountBusy.value = false; return }
  try { currentInstructor.value = await repository.saveInstructorProfile(profileForm.value); profileForm.value = { ...profileForm.value, ...currentInstructor.value }; accountMessage.value = t.value.saved }
  catch { accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}

async function saveVehicleSettings() {
  accountBusy.value = true; accountMessage.value = ''
  try {
    const saved = await repository.saveVehicle(vehicleForm.value)
    const index = currentInstructor.value.vehicles.findIndex((item) => item.id === saved.id)
    if (index >= 0) currentInstructor.value.vehicles[index] = saved; else currentInstructor.value.vehicles.push(saved)
    profileForm.value.vehicles = currentInstructor.value.vehicles
    resetVehicleForm()
    accountMessage.value = t.value.saved
  } catch { accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}

async function saveMeetingPointSettings() {
  accountBusy.value = true; accountMessage.value = ''
  try {
    const saved = await repository.saveMeetingPoint(meetingPointForm.value)
    const index = currentInstructor.value.meetingPoints.findIndex((item) => item.id === saved.id)
    if (index >= 0) currentInstructor.value.meetingPoints[index] = saved; else currentInstructor.value.meetingPoints.push(saved)
    profileForm.value.meetingPoints = currentInstructor.value.meetingPoints
    meetingPointForm.value = { id: null, city: 'Rīga', district: '', name: '', directions: '', surcharge: 0, isActive: true }
    accountMessage.value = t.value.saved
  } catch { accountMessage.value = t.value.saveError }
  finally { accountBusy.value = false }
}

async function loadSchoolDashboard() {
  const [statistics, management] = await Promise.all([
    repository.loadSchoolStatistics(widgetSchoolSlug, 30),
    repository.loadSchoolManagement(widgetSchoolSlug),
  ])
  schoolAnalytics.value = statistics
  schoolManagement.value = management
  schoolWidgetForm.value = {
    layout: management.school.settings?.layout || 'compact',
    theme: management.school.settings?.theme || 'ikars',
    accentColor: management.school.settings?.accentColor || '#0d827b',
    showPhotos: management.school.settings?.showPhotos !== false,
  }
}

async function saveSchoolWidgetAppearance() {
  schoolManagementBusy.value = true; schoolManagementMessage.value = ''
  try {
    await repository.saveSchoolWidgetSettings(widgetSchoolSlug, schoolWidgetForm.value)
    schoolManagement.value.school.settings = { ...schoolWidgetForm.value }
    schoolManagementMessage.value = t.value.appearanceSaved
    schoolWidgetSaved.value = true
  } catch (error) { console.error('School widget settings failed', error); schoolManagementMessage.value = t.value.managementError }
  finally { schoolManagementBusy.value = false }
}

async function previewSchoolWidget() {
  const previewWindow = window.open('', '_blank')
  try {
    await repository.saveSchoolWidgetSettings(widgetSchoolSlug, schoolWidgetForm.value)
    if (schoolManagement.value?.school) schoolManagement.value.school.settings = { ...schoolWidgetForm.value }
    schoolManagementMessage.value = t.value.appearanceSaved
    schoolWidgetSaved.value = true
    const returnUrl = window.location.href
    const previewUrl = `${window.location.origin}${window.location.pathname}?return=${encodeURIComponent(returnUrl)}#widget/${widgetSchoolSlug}/${schoolWidgetForm.value.layout}`
    if (previewWindow) previewWindow.location.href = previewUrl
    else window.location.href = previewUrl
  } catch (error) {
    if (previewWindow) previewWindow.close()
    console.error('School widget preview failed', error)
    schoolManagementMessage.value = t.value.managementError
  }
}

async function inviteSchoolInstructor() {
  schoolManagementBusy.value = true; schoolManagementMessage.value = ''
  try {
    await repository.inviteSchoolInstructor(widgetSchoolSlug, schoolInviteEmail.value.trim())
    schoolInviteEmail.value = ''
    await loadSchoolDashboard()
    schoolManagementMessage.value = t.value.invitationPrepared
  } catch (error) {
    console.error('School instructor invitation failed', error)
    schoolManagementMessage.value = (error.message || '').includes('Instructor profile was not found')
      ? t.value.instructorEmailNotFound
      : t.value.managementError
  } finally { schoolManagementBusy.value = false }
}

async function manageSchoolInstructor(item, action) {
  if (action === 'end' && !window.confirm(t.value.confirmEndLink)) return
  schoolManagementBusy.value = true; schoolManagementMessage.value = ''
  try {
    await repository.manageSchoolInstructor(widgetSchoolSlug, item.linkId, action)
    await loadSchoolDashboard()
  } catch (error) {
    console.error('School instructor management failed', error)
    schoolManagementMessage.value = (error.message || '').includes('WIDGET_SCHOOL_LIMIT_BASIC')
      ? t.value.widgetSchoolLimit
      : t.value.managementError
  } finally { schoolManagementBusy.value = false }
}

function schoolLinkStatus(status) {
  return t.value[status === 'active' ? 'activeLink' : status === 'paused' ? 'pausedLink' : status === 'ended' ? 'endedLink' : 'invitedLink']
}

async function signIn() {
  authError.value = ''
  authBusy.value = true
  try {
    session.value = await repository.signIn(authEmail.value.trim(), authPassword.value)
    authPassword.value = ''
  } catch {
    session.value = null
    authError.value = authCopy.value.genericError
    authBusy.value = false
    return
  }
  try {
    if (schoolDashboardMode) await loadSchoolDashboard()
    else if (platformAdminMode) await loadPlatformAdminDashboard()
    else await loadWorkspace()
  } catch (error) {
    console.error('Sign-in workspace load failed', JSON.stringify(error))
    studentRecords.value = []
    schedule.value = []
    authError.value = t.value.saveError
  } finally {
    authBusy.value = false
  }
}

async function signOut() {
  await repository.signOut()
  session.value = null
  studentRecords.value = []
  schedule.value = []
}

onMounted(async () => {
  document.addEventListener('keydown', handleGlobalKeydown)
  if (studentScheduleMode) {
    try {
      studentSchedule.value = await repository.loadStudentPersonalSchedule(studentScheduleToken)
      studentScheduleError.value = !studentSchedule.value
    } catch (error) {
      console.error('Student personal schedule load failed', JSON.stringify(error))
      studentScheduleError.value = true
    } finally { dataReady.value = true }
    return
  }
  if (publicDirectoryMode) {
    dataReady.value = true
    try {
      if (publicWidgetMode) {
        const widget = await repository.loadSchoolWidget(widgetSchoolSlug, isoDate(new Date()), 42)
        widgetSchool.value = widget?.school || null
        if (!widgetLayoutExplicit && ['banner', 'compact', 'full'].includes(widget?.school?.settings?.layout)) widgetLayout.value = widget.school.settings.layout
        publicInstructors.value = widget?.instructors || []
      } else publicInstructors.value = await repository.loadPublicDirectory(isoDate(new Date()), 42)
    }
    catch (error) { console.error('Public directory load failed', JSON.stringify(error)); publicInstructors.value = [] }
    publicEvent('widget_view')
    analytics.value.views += 1
    setVisibleActivity(); document.addEventListener('visibilitychange', setVisibleActivity)
    activeTimer = window.setInterval(() => { if (activeStartedAt) { const elapsed = Math.round((Date.now() - activeStartedAt) / 1000); analytics.value.activeSeconds += elapsed; publicActiveSeconds += elapsed; activeStartedAt = Date.now() } }, 10000)
    await nextTick()
    reportWidgetHeight()
    widgetResizeObserver = new ResizeObserver(reportWidgetHeight)
    widgetResizeObserver.observe(document.querySelector('.widget-page') || document.body)
    window.addEventListener('resize', reportWidgetHeight)
    return
  }
  try {
    session.value = await repository.getSession()
    if (session.value) {
      if (schoolDashboardMode) await loadSchoolDashboard()
      else if (platformAdminMode) await loadPlatformAdminDashboard()
      else await loadWorkspace()
    }
  } catch (error) {
    console.error('Initial workspace load failed', JSON.stringify(error))
    if (repository.mode !== 'demo') { studentRecords.value = []; schedule.value = [] }
    authError.value = authCopy.value.genericError
  } finally {
    dataReady.value = true
  }
  if (session.value && !schoolDashboardMode) { analytics.value.views += 1; persistAnalytics() }
  setVisibleActivity(); document.addEventListener('visibilitychange', setVisibleActivity)
  activeTimer = window.setInterval(() => { if (activeStartedAt) { analytics.value.activeSeconds += Math.round((Date.now() - activeStartedAt) / 1000); activeStartedAt = Date.now() } }, 10000)
})
watch([transmission, vehicleMake, district, serviceType], ([nextTransmission, nextMake, nextDistrict, nextService], previous) => {
  if (publicDirectoryMode && previous) publicEvent('filter_used', null, { transmission: nextTransmission, vehicleMake: nextMake, district: nextDistrict, service: nextService })
})
onBeforeUnmount(() => { clearInterval(activeTimer); widgetResizeObserver?.disconnect(); window.removeEventListener('resize', reportWidgetHeight); document.removeEventListener('visibilitychange', setVisibleActivity); document.removeEventListener('keydown', handleGlobalKeydown); if (publicDirectoryMode && activeStartedAt) { publicActiveSeconds += Math.round((Date.now() - activeStartedAt) / 1000); publicEvent('session_end', null, {}, publicActiveSeconds) }; setVisibleActivity() })
</script>

<template>
  <main v-if="!dataReady" class="auth-page"><div class="auth-card"><div class="brand">IKARS <span>INSTRUCTOR</span></div><p>{{ authCopy.loading }}</p></div></main>
  <main v-else-if="!session && !publicAccessMode" class="auth-page">
    <form class="auth-card" @submit.prevent="signIn">
      <div class="auth-head"><div class="brand">IKARS <span>INSTRUCTOR</span></div><button type="button" @click="language = language === 'LV' ? 'RU' : 'LV'">{{ language }}</button></div>
      <h1>{{ authCopy.title }}</h1><p>{{ authCopy.subtitle }}</p>
      <label>{{ authCopy.email }}<input v-model="authEmail" type="email" autocomplete="email" required></label>
      <label>{{ authCopy.password }}<input v-model="authPassword" type="password" autocomplete="current-password" required></label>
      <p v-if="authError" class="form-error">{{ authError }}</p>
      <button class="primary" :disabled="authBusy">{{ authBusy ? authCopy.signingIn : authCopy.signIn }}</button>
    </form>
  </main>
  <main v-else :class="{ 'widget-shell': publicWidgetMode }">
    <div v-if="saveNotice" class="save-notice" role="status" aria-live="polite">✓ {{ saveNotice }}</div>
    <header v-if="!publicWidgetMode" class="topbar"><div class="brand">IKARS <span>{{ studentScheduleMode ? 'STUDENT' : (platformAdminMode ? 'PLATFORM' : (schoolDashboardMode ? t.schoolStatistics.toUpperCase() : 'INSTRUCTOR')) }}</span></div><div class="top-actions"><span v-if="!studentScheduleMode" class="demo">{{ platformAdminMode ? 'SUPABASE TEST' : (publicDirectoryMode ? t.publicPreview : (repository.mode === 'demo' ? 'DEMO' : 'TEST')) }}</span><button v-if="!publicAccessMode && !schoolDashboardMode && !platformAdminMode && repository.mode !== 'demo'" @click="openAccount">⚙ {{ t.account }}</button><button @click="language = language === 'LV' ? 'RU' : 'LV'">{{ language }}</button><button v-if="!publicAccessMode && repository.mode !== 'demo'" @click="signOut">{{ authCopy.signOut }}</button></div></header>
    <nav v-if="platformAdminMode" class="tabs school-tabs"><button class="active">{{ t.platformOverview }}</button></nav>
    <nav v-else-if="schoolDashboardMode" class="tabs school-tabs"><button class="active">{{ t.schoolStatistics }}</button></nav>
    <nav v-else-if="!publicAccessMode" class="tabs"><button :class="{ active: view === 'calendar' }" @click="view = 'calendar'">{{ t.calendar }}</button><button :class="{ active: view === 'students' }" @click="view = 'students'">{{ t.students }}</button><button :class="{ active: view === 'statistics' }" @click="view = 'statistics'">{{ t.statistics }}</button><button @click="openPublicDirectory">{{ t.publicPreview }} ↗</button></nav>
    <nav v-else-if="publicDirectoryMode && !publicWidgetMode" class="tabs public-tabs"><button class="active">{{ t.directory }}</button><button @click="openInstructorCabinet">{{ t.backToCabinet }}</button></nav>

    <section v-if="view === 'student-schedule'" class="page student-schedule-page">
      <div v-if="studentScheduleError" class="student-schedule-error"><div class="brand">IKARS <span>STUDENT</span></div><h1>{{ t.invalidStudentLink }}</h1></div>
      <template v-else-if="studentSchedule">
        <header class="student-schedule-hero"><small>IKARS · STUDENT</small><h1>{{ t.personalSchedule }}</h1><p>{{ studentSchedule.student.firstName }} {{ studentSchedule.student.lastName }} · {{ t.personalScheduleHelp }}</p></header>
        <div class="student-schedule-stats"><article v-if="studentSchedule.statistics.showFullHistory"><span>{{ t.completedLessons }}</span><strong>{{ studentSchedule.statistics.completedLessons }}</strong></article><article v-if="studentSchedule.statistics.showFullHistory"><span>{{ t.chargedTotal }}</span><strong>€{{ Number(studentSchedule.statistics.chargedAmount || 0).toFixed(2) }}</strong></article><article v-if="studentSchedule.statistics.showFullHistory"><span>{{ t.totalPaidByStudent }}</span><strong>€{{ Number(studentSchedule.statistics.paidAmount || 0).toFixed(2) }}</strong></article><article v-if="studentSchedule.statistics.showFullHistory" :class="{ debt: studentSchedule.statistics.debtAmount > 0, credit: studentSchedule.statistics.creditAmount > 0 }"><span>{{ studentSchedule.statistics.debtAmount > 0 ? t.debt : (studentSchedule.statistics.creditAmount > 0 ? t.credit : t.settlementClosed) }}</span><strong v-if="studentSchedule.statistics.debtAmount > 0">€{{ Number(studentSchedule.statistics.debtAmount).toFixed(2) }}</strong><strong v-else-if="studentSchedule.statistics.creditAmount > 0">€{{ Number(studentSchedule.statistics.creditAmount).toFixed(2) }}</strong><strong v-else>✓</strong></article><template v-else><article :class="{ debt: studentSchedule.statistics.debtAmount > 0 }"><span>{{ t.debt }}</span><strong>€{{ Number(studentSchedule.statistics.debtAmount || 0).toFixed(2) }}</strong></article><article :class="{ credit: studentSchedule.statistics.creditAmount > 0 }"><span>{{ t.credit }}</span><strong>€{{ Number(studentSchedule.statistics.creditAmount || 0).toFixed(2) }}</strong></article></template></div>
        <section class="student-schedule-section"><h2>{{ t.nextLessons }}</h2><p v-if="!studentUpcomingLessons.length">{{ t.noUpcomingLessons }}</p><article v-for="lesson in studentUpcomingLessons" :key="lesson.id" class="student-lesson-card"><div><time>{{ new Date(lesson.startsAt).toLocaleDateString(t.locale, { weekday: 'long', day: 'numeric', month: 'long' }) }}</time><strong>{{ new Date(lesson.startsAt).toLocaleTimeString(t.locale, { hour: '2-digit', minute: '2-digit' }) }}–{{ new Date(lesson.endsAt).toLocaleTimeString(t.locale, { hour: '2-digit', minute: '2-digit' }) }}</strong></div><div><b>{{ studentSchedule.instructor.firstName }} {{ studentSchedule.instructor.lastName }}</b><span v-if="lesson.vehicle">{{ lesson.vehicle.transmission === 'automatic' ? 'A' : 'M' }} · {{ lesson.vehicle.model }}</span><small v-if="lesson.meetingPoint">{{ lesson.meetingPoint.district }} · {{ lesson.meetingPoint.name }}</small></div><em :class="{ paid: lesson.paid }">{{ lesson.paid ? t.paidStatus : t.unpaid }}</em></article></section>
        <section v-if="studentPastScheduleLessons.length" class="student-schedule-section past"><h2>{{ t.pastLessons }}</h2><article v-for="lesson in studentPastScheduleLessons" :key="lesson.id" class="student-lesson-card"><div><time>{{ new Date(lesson.startsAt).toLocaleDateString(t.locale, { day: 'numeric', month: 'long', year: 'numeric' }) }}</time><strong>{{ new Date(lesson.startsAt).toLocaleTimeString(t.locale, { hour: '2-digit', minute: '2-digit' }) }}</strong></div><div><b>{{ t[lesson.status === 'no_show' ? 'noShow' : lesson.status] }}</b><span v-if="lesson.vehicle">{{ lesson.vehicle.model }}</span></div><em :class="{ paid: lesson.paid }">{{ lesson.paid ? t.paidStatus : t.unpaid }}</em></article></section>
        <a class="student-info-portal" href="https://info.ikars.lv/" target="_blank" rel="noopener"><span><b>{{ t.ikarsInfoPortal }}</b><small>{{ t.ikarsInfoPortalHelp }}</small></span><strong>IKARS →</strong></a>
        <a v-if="studentSchedule.instructor.phone" class="student-instructor-call" :href="`tel:${studentSchedule.instructor.phone.replace(/\s/g, '')}`">☎ {{ studentSchedule.instructor.phone }}</a>
      </template>
    </section>

    <aside v-if="showBackupReminder && !publicDirectoryMode && !schoolDashboardMode && repository.mode !== 'demo'" class="backup-reminder" role="status"><span>▣</span><p>{{ t.backupAlert }}</p><button type="button" class="backup-download" @click="exportCalendarXls">{{ t.downloadNow }}</button><button type="button" @click="snoozeBackupReminder">{{ t.remindLater }}</button></aside>

    <aside v-if="showBillingNotice && !publicDirectoryMode && !schoolDashboardMode && !platformAdminMode" :class="['billing-notice', `billing-${effectiveBillingState}`]" role="status"><div><strong>{{ effectiveBillingState === '7' ? t.billingSevenTitle : effectiveBillingState === '3' ? t.billingThreeTitle : effectiveBillingState === 'termination' ? t.billingTerminationTitle : t.billingExpiredTitle }}</strong><p>{{ effectiveBillingState === '7' ? t.billingSevenText : effectiveBillingState === '3' ? t.billingThreeText : effectiveBillingState === 'termination' ? t.billingTerminationText : t.billingExpiredText }}</p><small v-if="billingReadOnly && billingExportAllowed">✓ {{ t.exportStillAvailable }}</small><small v-else-if="billingReadOnly">{{ t.exportLocked }}</small></div><div class="billing-actions"><button v-if="!billingPaymentReported && effectiveBillingState !== 'termination'" type="button" class="primary" @click="reportBillingPayment">{{ t.iPaid }}</button><span v-else-if="billingPaymentReported">✓ {{ t.paymentReported }}</span><button v-if="effectiveBillingState === '7'" type="button" @click="dismissBillingReminder">{{ t.dismissReminder }}</button></div></aside>

    <section v-if="view === 'platform-admin'" class="page platform-admin-page">
      <div class="page-head"><div><small>IKARS PLATFORM</small><h1>{{ t.platformAdmin }}</h1></div><span class="prototype-note">SUPABASE TEST</span></div>
      <p v-if="platformAdminError" class="form-error">{{ platformAdminError }}</p>
      <p v-if="platformAdminBusy">{{ authCopy.loading }}</p>
      <div class="platform-metrics"><article><span>{{ t.activeSubscriptions }}</span><strong>{{ platformMetrics.subscriptions }}</strong></article><article><span>{{ t.monthlyRevenue }}</span><strong>€{{ platformMetrics.revenue }}</strong></article><article class="attention"><span>{{ t.needsAttention }}</span><strong>{{ platformMetrics.attention }}</strong></article><article class="attention"><span>{{ t.expiringSoon }}</span><strong>{{ platformMetrics.expiring }}</strong></article><article><span>{{ t.schoolsCount }}</span><strong>{{ platformMetrics.schools }}</strong></article></div>
      <section class="platform-section payment-claims"><h2>{{ t.paymentClaims }}</h2><p v-if="!platformPaymentClaims.length">{{ t.noPaymentClaims }}</p><article v-for="claim in platformPaymentClaims" :key="claim.id"><div><strong>{{ claim.instructor }}</strong><small>{{ claim.createdAt }}</small></div><span :class="['claim-status', claim.status]">{{ claim.status === 'pending' ? t.paymentClaimPending : claim.status === 'confirmed' ? t.paymentClaimConfirmed : t.paymentClaimRejected }}</span><div v-if="claim.status === 'pending'"><button type="button" class="confirm" @click="resolvePaymentClaim(claim, 'confirmed')">{{ t.confirmPayment }}</button><button type="button" @click="resolvePaymentClaim(claim, 'rejected')">{{ t.rejectPayment }}</button></div><small v-else>{{ claim.resolvedAt }}</small></article></section>
      <section class="platform-section"><h2>{{ t.platformSchools }}</h2><div class="school-overview-grid"><article v-for="school in platformDemoSchools" :key="school.id" class="platform-open-card" @click="openPlatformSchool(school)"><div><strong>{{ school.name }}</strong><span>{{ school.city || '—' }}</span><a v-if="school.phone" :href="`tel:${school.phone.replace(/\s/g, '')}`" @click.stop>{{ school.phone }}</a><span v-else>—</span><small>{{ school.email || '—' }}</small></div><dl><div><dt>{{ t.instructorResults }}</dt><dd>{{ school.instructors }}</dd></div><div><dt>Widget</dt><dd>{{ school.widget }}</dd></div></dl><em :class="school.status">{{ school.status === 'active' ? t.activeSubscription : (school.status === 'pilot' ? t.pilotStatus : t.demoStatus) }}</em></article></div></section>
      <section class="platform-section">
        <div class="platform-section-head">
          <div><h2>{{ t.platformInstructors }}</h2><small>{{ t.foundInstructors }}: {{ filteredPlatformInstructors.length }}</small></div>
          <div class="platform-filters">
            <input v-model="platformSearch" :placeholder="t.searchInstructor">
            <select v-model="platformSchoolFilter"><option value="ALL">{{ t.allSchools }}</option><option value="NONE">{{ t.noSchool }}</option><option v-for="school in platformDemoSchools" :key="school.id" :value="school.name">{{ school.name }}</option></select>
            <select v-model="platformPlanFilter"><option value="ALL">{{ t.allPlans }}</option><option value="profile">Profile</option><option value="basic">Basic</option><option value="pro">Pro</option></select>
            <select v-model="platformStatusFilter"><option value="ALL">{{ t.allStatuses }}</option><option value="active">{{ t.activeSubscription }}</option><option value="trial">{{ t.trialSubscription }}</option><option value="paused">{{ t.pausedSubscription }}</option></select>
            <select v-model="platformExpiryFilter"><option value="ALL">{{ t.expiryAll }}</option><option value="14">{{ t.expiry14 }}</option><option value="30">{{ t.expiry30 }}</option><option value="EXPIRED">{{ t.expiryExpired }}</option></select>
          </div>
        </div>
        <div class="platform-table-wrap"><table><thead><tr><th>{{ t.platformInstructor }}</th><th>{{ t.school }}</th><th>{{ t.plan }}</th><th>{{ t.subscriptionAgreedPrice }}</th><th>{{ t.status }}</th><th>{{ t.paidPeriod }}</th><th>{{ t.paymentBalance }}</th><th>{{ t.paidThrough }}</th><th>{{ t.daysRemaining }}</th></tr></thead><tbody><tr v-for="item in filteredPlatformInstructors" :key="item.id" class="platform-open-row" @click="openPlatformInstructor(item)"><td><strong>{{ item.name }}</strong><a v-if="item.phone" :href="`tel:${item.phone.replace(/\s/g, '')}`" @click.stop>{{ item.phone }}</a><small v-else>—</small></td><td><div v-if="item.schools.length" class="school-tags"><span v-for="school in item.schools" :key="school">{{ school }}</span></div><small v-else>{{ t.noSchool }}</small></td><td><b :class="['plan-badge', item.plan]">{{ item.plan }}</b></td><td><strong>€{{ item.agreedAmount || 0 }}</strong></td><td><span :class="['subscription-status', item.status]">{{ platformStatusLabel(item.status) }}</span></td><td>{{ item.periodMonths || '—' }}<template v-if="item.periodMonths"> {{ t.monthsShort }} · €{{ item.paidAmount }}</template></td><td><span :class="['subscription-payment-state', item.paymentState]">€{{ item.balance }} · {{ subscriptionPaymentLabel(item.paymentState) }}</span></td><td>{{ item.paidThrough }}</td><td><span :class="['payment-time', platformPaymentClass(item)]">{{ platformDaysLabel(item) }}</span></td></tr></tbody></table></div>
      </section>
      <section class="platform-section platform-audit"><h2>{{ t.adminHistory }}</h2><p v-if="!platformAuditLog.length">{{ t.noAdminHistory }}</p><article v-for="entry in platformAuditLog" :key="entry.id"><time>{{ entry.time }}</time><strong>{{ entry.instructor }}</strong><span>{{ entry.change }}</span><small v-if="entry.note">{{ entry.note }}</small></article></section>
    </section>

    <div v-if="selectedPlatformInstructor" class="modal" @click.self="selectedPlatformInstructor = null"><section class="platform-detail-card"><div class="modal-head"><div><small>IKARS PLATFORM</small><h2>{{ selectedPlatformInstructor.name }}</h2></div><button type="button" @click="selectedPlatformInstructor = null">×</button></div><div class="platform-detail-grid"><div><span>{{ t.phone }}</span><a :href="`tel:${selectedPlatformInstructor.phone.replace(/\s/g, '')}`">{{ selectedPlatformInstructor.phone }}</a></div><div><span>{{ t.email }}</span><b>{{ selectedPlatformInstructor.email }}</b></div><div><span>{{ t.lastPaymentDate }}</span><b>{{ selectedPlatformInstructor.paidAt }}</b></div><div><span>{{ t.paidPeriod }}</span><b>{{ selectedPlatformInstructor.periodMonths || '—' }}<template v-if="selectedPlatformInstructor.periodMonths"> {{ t.monthsShort }}</template></b></div><div><span>{{ t.paidAmount }}</span><b>€{{ selectedPlatformInstructor.paidAmount }}</b></div><div><span>{{ t.paidThrough }}</span><b>{{ selectedPlatformInstructor.paidThrough }}</b></div><div><span>{{ t.daysRemaining }}</span><b :class="['payment-time', platformPaymentClass(selectedPlatformInstructor)]">{{ platformDaysLabel(selectedPlatformInstructor) }}</b></div><div><span>{{ t.monthlyPrice }}</span><b>€{{ selectedPlatformInstructor.monthly }}</b></div></div><h3>{{ t.cooperationSchools }}</h3><div v-if="selectedPlatformInstructor.schools.length" class="school-tags"><span v-for="school in selectedPlatformInstructor.schools" :key="school">{{ school }}</span></div><p v-else>{{ t.noSchool }}</p><div class="billing-preview-links"><strong>{{ t.previewBilling }}</strong><a href="/?billing-demo=7" target="_blank">{{ t.preview7 }}</a><a href="/?billing-demo=3" target="_blank">{{ t.preview3 }}</a><a href="/?billing-demo=expired" target="_blank">{{ t.previewExpired }}</a><a href="/?billing-demo=termination" target="_blank">{{ t.previewTermination }}</a></div><div class="grace-actions"><strong>{{ t.grantGrace }}</strong><button v-for="days in [3,7,14]" :key="days" type="button" @click="extendPlatformGrace(days)">+{{ days }} {{ t.daysShort }}</button></div><form class="platform-subscription-form" @submit.prevent="savePlatformSubscription"><h3>{{ t.subscriptionManagement }}</h3><div class="form-grid"><label>{{ t.plan }}<select v-model="platformSubscriptionForm.plan"><option value="profile">Profile</option><option value="basic">Basic</option><option value="pro">Pro</option></select></label><label>{{ t.status }}<select v-model="platformSubscriptionForm.status"><option value="active">{{ t.activeSubscription }}</option><option value="trial">{{ t.trialSubscription }}</option><option value="paused">{{ t.pausedSubscription }}</option></select></label></div><div class="form-grid"><label>{{ t.lastPaymentDate }}<input v-model="platformSubscriptionForm.paidAt" type="date"></label><label>{{ t.paidPeriod }}<select v-model.number="platformSubscriptionForm.periodMonths"><option :value="1">1 {{ t.monthsShort }}</option><option :value="3">3 {{ t.monthsShort }}</option><option :value="6">6 {{ t.monthsShort }}</option><option :value="12">12 {{ t.monthsShort }}</option></select></label></div><label>{{ t.paidAmount }}<input v-model.number="platformSubscriptionForm.paidAmount" type="number" min="0" step="0.01"></label><label>{{ t.adminNote }}<textarea v-model="platformSubscriptionForm.note" rows="2" :placeholder="t.adminNotePlaceholder"></textarea></label><button :class="['primary', { saved: platformSubscriptionSaved }]">{{ platformSubscriptionSaved ? `✓ ${t.subscriptionSaved}` : t.saveSubscription }}</button></form></section></div>

    <div v-if="selectedPlatformSchool" class="modal" @click.self="selectedPlatformSchool = null"><section class="platform-detail-card"><div class="modal-head"><div><small>IKARS PLATFORM</small><h2>{{ selectedPlatformSchool.name }}</h2></div><button type="button" @click="selectedPlatformSchool = null">×</button></div><div class="platform-detail-grid"><div><span>{{ t.city }}</span><b>{{ selectedPlatformSchool.city }}</b></div><div><span>{{ t.phone }}</span><a :href="`tel:${selectedPlatformSchool.phone.replace(/\s/g, '')}`">{{ selectedPlatformSchool.phone }}</a></div><div><span>{{ t.email }}</span><b>{{ selectedPlatformSchool.email }}</b></div><div><span>{{ t.widgetMode }}</span><b>{{ selectedPlatformSchool.widget }}</b></div></div><h3>{{ t.linkedInstructors }}</h3><div class="platform-linked-list"><button v-for="instructor in platformSchoolInstructors(selectedPlatformSchool)" :key="instructor.id" type="button" @click="openPlatformInstructor(instructor)"><strong>{{ instructor.name }}</strong><span>{{ instructor.phone }}</span><b>{{ instructor.plan }}</b></button></div></section></div>

    <Teleport v-if="selectedPlatformInstructor" to=".platform-detail-card"><form class="platform-subscription-form termination-form" @submit.prevent="savePlatformTermination(false)"><h3>{{ t.terminationManagement }}</h3><p class="form-help">{{ t.terminationHelp }}</p><div class="form-grid"><label>{{ t.terminationDate }}<input v-model="platformTerminationForm.effectiveOn" type="date" required></label><label>{{ t.exportAccessUntil }}<input v-model="platformTerminationForm.exportAccessUntil" type="date" :min="platformTerminationForm.effectiveOn || undefined"></label></div><label>{{ t.adminNote }}<textarea v-model="platformTerminationForm.note" rows="2" :placeholder="t.adminNotePlaceholder"></textarea></label><div class="termination-actions"><button class="primary" :disabled="platformAdminBusy">{{ platformTerminationSaved ? `✓ ${t.terminationSaved}` : t.scheduleTermination }}</button><button v-if="selectedPlatformInstructor.terminationEffectiveOn" type="button" class="secondary" :disabled="platformAdminBusy" @click="savePlatformTermination(true)">{{ t.cancelTermination }}</button></div></form></Teleport>

    <Teleport v-if="view === 'platform-admin'" defer to=".school-overview-grid"><article class="platform-school-create-card"><button v-if="!showPlatformSchoolForm" type="button" class="platform-add-school" @click="showPlatformSchoolForm = true">+ {{ t.addPlatformSchool }}</button><form v-else @submit.prevent="createPlatformSchool"><div class="platform-section-head"><h3>{{ t.newPlatformSchool }}</h3><button type="button" @click="showPlatformSchoolForm = false">×</button></div><label>{{ t.school }}<input v-model="platformSchoolForm.name" required minlength="2"></label><label>{{ t.schoolSystemAddress }}<input v-model.trim="platformSchoolForm.slug" required pattern="[a-z0-9]+(?:-[a-z0-9]+)*" placeholder="pilota-autoskola"></label><label>{{ t.schoolAdminEmail }}<input v-model.trim="platformSchoolForm.adminEmail" type="email" required></label><small>{{ t.schoolAdminHelp }}</small><div class="form-grid"><label>{{ t.email }}<input v-model.trim="platformSchoolForm.email" type="email"></label><label>{{ t.phone }}<input v-model.trim="platformSchoolForm.phone" type="tel"></label></div><label>{{ t.schoolRegistrationNumber }}<input v-model.trim="platformSchoolForm.registrationNumber"></label><label>{{ t.schoolWebsite }}<input v-model.trim="platformSchoolForm.websiteUrl" type="url" placeholder="https://"></label><button class="primary" :disabled="platformAdminBusy">{{ platformSchoolCreated ? `✓ ${t.platformSchoolCreated}` : t.createPlatformSchool }}</button></form></article></Teleport>

    <Teleport v-if="view === 'platform-admin' && platformAdminError" defer to=".platform-school-create-card"><p class="form-error platform-school-form-result" role="alert">{{ platformAdminError }}</p></Teleport>
    <Teleport v-if="selectedPlatformInstructor" defer to=".platform-detail-grid"><div><span>{{ t.activeWidgetSchools }}</span><b>{{ selectedPlatformInstructor.widgetSchoolCount || 0 }}</b></div><div><span>{{ t.subscriptionAgreedPrice }}</span><b>€{{ selectedPlatformInstructor.agreedAmount || 0 }}</b></div><div><span>{{ t.paymentBalance }}</span><b>€{{ selectedPlatformInstructor.balance || 0 }} · {{ subscriptionPaymentLabel(selectedPlatformInstructor.paymentState) }}</b></div></Teleport>
    <Teleport v-if="selectedPlatformInstructor && platformSubscriptionSaved" defer to=".platform-subscription-form"><p class="school-management-message" role="status">✓ {{ t.subscriptionSaved }}</p></Teleport>
    <Teleport v-if="selectedPlatformInstructor" defer to=".platform-subscription-form"><section class="custom-price-controls"><div><span>{{ t.subscriptionStandardPrice }}</span><strong>€{{ selectedStandardPrice }}</strong></div><label class="custom-price-toggle"><input v-model="platformSubscriptionForm.customPriceEnabled" type="checkbox"><span>{{ t.useCustomPrice }}</span></label><label v-if="platformSubscriptionForm.customPriceEnabled">{{ t.customPrice }}<input v-model.number="platformSubscriptionForm.customAmount" type="number" min="0" step="0.01" required></label><button v-if="platformSubscriptionForm.customPriceEnabled" type="button" class="secondary" @click="platformSubscriptionForm.customPriceEnabled = false; platformSubscriptionForm.customAmount = selectedStandardPrice">{{ t.restoreStandardPrice }}</button></section></Teleport>
    <Teleport v-if="selectedPlatformInstructor" defer to=".platform-subscription-form"><section :class="['subscription-payment-summary', `state-${selectedPaymentState}`]"><div><span>{{ t.subscriptionAgreedPrice }}</span><strong>€{{ selectedAgreedPrice }}</strong></div><div><span>{{ t.paidAmount }}</span><strong>€{{ Number(platformSubscriptionForm.paidAmount || 0) }}</strong></div><div><span>{{ t.paymentBalance }}</span><strong>€{{ selectedPaymentBalance }}</strong></div><b>{{ subscriptionPaymentLabel(selectedPaymentState) }}</b><button type="button" class="secondary" @click="markPlatformSubscriptionPaid">✓ {{ t.markPaidInFull }}</button></section></Teleport>
    <Teleport v-if="view === 'platform-admin'" defer to=".platform-admin-page"><section class="platform-section platform-pricing"><div class="platform-section-head"><div><h2>{{ t.planPricing }}</h2><small>{{ t.planPricingHelp }}</small></div></div><form @submit.prevent="savePlatformPrices"><div class="pricing-grid"><article v-for="plan in ['profile','basic','pro']" :key="plan"><h3>{{ plan[0].toUpperCase() + plan.slice(1) }}</h3><label v-for="price in pricesForPlan(plan)" :key="`${plan}-${price.periodMonths}`"><span>{{ price.periodMonths }} {{ t.monthsShort }}</span><input v-model.number="price.totalAmount" type="number" min="0" step="0.01" required><b>€</b></label></article></div><button :class="['primary', { saved: platformPricesSaved }]" :disabled="platformAdminBusy">{{ platformPricesSaved ? `✓ ${t.planPricesSaved}` : t.savePlanPrices }}</button><p v-if="platformPricesSaved" class="school-management-message" role="status">✓ {{ t.planPricesSaved }}</p></form></section></Teleport>

    <section v-if="view === 'school-statistics'" class="page school-statistics-page">
      <div class="page-head"><div><small>{{ t.lastDays }}</small><h1>{{ schoolAnalytics?.school?.name || t.schoolStatistics }}</h1></div></div>
      <p v-if="!schoolAnalytics" class="analytics-note">{{ t.noSchoolAccess }}</p>
      <template v-else>
        <div class="stats school-stats"><article><span>{{ t.widgetViews }}</span><strong>{{ schoolAnalytics.widgetViews }}</strong></article><article><span>{{ t.profiles }}</span><strong>{{ schoolAnalytics.profileViews }}</strong></article><article><span>{{ t.calls }}</span><strong>{{ schoolAnalytics.phoneClicks }}</strong></article><article><span>{{ t.filterUses }}</span><strong>{{ schoolAnalytics.filterUses }}</strong></article><article><span>{{ t.uniqueVisitors }}</span><strong>{{ schoolAnalytics.uniqueSessions }}</strong></article><article><span>{{ t.activeMinutes }}</span><strong>{{ Math.round((schoolAnalytics.activeSeconds || 0) / 60) }}</strong></article></div>
        <section class="school-instructor-results"><h2>{{ t.instructorResults }}</h2><div class="school-results-head"><span>{{ t.directory }}</span><span>{{ t.profiles }}</span><span>{{ t.calls }}</span></div><article v-for="item in schoolAnalytics.instructors" :key="item.id"><strong>{{ item.name }}</strong><span>{{ item.profileViews }}</span><span>{{ item.phoneClicks }}</span></article></section>
        <form v-if="schoolManagement?.school.role === 'admin'" class="school-widget-settings" @submit.prevent="saveSchoolWidgetAppearance">
          <div class="school-team-head"><h2>{{ t.widgetAppearance }}</h2></div>
          <label>{{ t.widgetLayoutLabel }}<span class="setting-options"><button v-for="mode in ['banner','compact','full']" :key="mode" type="button" :class="{ active: schoolWidgetForm.layout === mode }" @click="schoolWidgetForm.layout = mode">{{ mode[0].toUpperCase() + mode.slice(1) }}</button></span></label>
          <label>{{ t.widgetThemeLabel }}<span class="theme-options"><button v-for="theme in ['ikars','baltic','sand','graphite','custom']" :key="theme" type="button" :class="['theme-swatch', `swatch-${theme}`, { active: schoolWidgetForm.theme === theme }]" @click="schoolWidgetForm.theme = theme"><i></i>{{ theme === 'custom' ? t.customSchoolColor : t[`theme${theme[0].toUpperCase() + theme.slice(1)}`] }}</button></span></label>
          <label v-if="schoolWidgetForm.theme === 'custom'" class="custom-color">{{ t.customSchoolColor }}<input v-model="schoolWidgetForm.accentColor" type="color"></label>
          <label>{{ t.profilePhoto }}<span class="setting-options photo-setting"><button type="button" :class="{ active: schoolWidgetForm.showPhotos }" @click="schoolWidgetForm.showPhotos = true">{{ t.showInstructorPhotos }}</button><button type="button" :class="{ active: !schoolWidgetForm.showPhotos }" @click="schoolWidgetForm.showPhotos = false">{{ t.hideInstructorPhotos }}</button></span></label>
          <div :class="['widget-settings-preview', `preview-${schoolWidgetForm.theme}`]" :style="schoolWidgetForm.theme === 'custom' ? { '--preview-accent': schoolWidgetForm.accentColor } : {}"><small>{{ t.preview }}</small><div><span v-if="schoolWidgetForm.showPhotos" class="preview-photo">AB</span><span v-else class="preview-initials">AB</span><p><b>Andris Bērziņš</b><em>B · Volkswagen Golf</em></p><button type="button" @click="previewSchoolWidget">{{ t.showCalendar }}</button></div></div>
          <div class="widget-settings-actions"><button type="button" class="secondary" :disabled="schoolManagementBusy" @click="previewSchoolWidget">↗ {{ t.openLargePreview }}</button><button :class="['primary', 'save-widget-settings', { saved: schoolWidgetSaved }]" :disabled="schoolManagementBusy">{{ schoolWidgetSaved ? `✓ ${t.appearanceSaved}` : t.saveAppearance }}</button></div>
        </form>
        <section v-if="schoolManagement" class="school-team">
          <div class="school-team-head"><h2>{{ t.schoolTeam }}</h2><span>{{ schoolManagement.instructors.length }}</span></div>
          <form v-if="schoolManagement.school.role === 'admin'" class="school-invite" @submit.prevent="inviteSchoolInstructor"><label>{{ t.instructorEmail }}<input v-model="schoolInviteEmail" type="email" required placeholder="instructor@example.com"></label><button class="primary" :disabled="schoolManagementBusy">+ {{ t.inviteInstructor }}</button></form>
          <p v-else class="analytics-note">{{ t.adminOnly }}</p>
          <p v-if="schoolManagementMessage" class="school-management-message">{{ schoolManagementMessage }}</p>
          <div class="school-team-list">
            <article v-for="item in schoolManagement.instructors" :key="item.linkId">
              <div><strong>{{ item.name }}</strong><span>{{ item.email || item.phone || '—' }}</span><small>{{ item.plan }} · {{ t.activeWidgetSchools }}: {{ item.visibleWidgetCount || 0 }}</small><small :class="`link-${item.status}`">{{ schoolLinkStatus(item.status) }}</small><em v-if="item.status === 'active'">{{ item.showInWidget ? t.visibleInWidget : t.hiddenInWidget }}</em></div>
              <div v-if="schoolManagement.school.role === 'admin'" class="school-team-actions">
                <button v-if="item.status === 'active'" @click="manageSchoolInstructor(item, item.showInWidget ? 'hide' : 'show')">{{ item.showInWidget ? t.hideFromWidget : t.showInWidget }}</button>
                <button v-if="item.status === 'active'" @click="manageSchoolInstructor(item, 'pause')">{{ t.pauseLink }}</button>
                <button v-if="item.status === 'paused'" @click="manageSchoolInstructor(item, 'resume')">{{ t.resumeLink }}</button>
                <button v-if="item.status !== 'ended'" class="danger-action" @click="manageSchoolInstructor(item, 'end')">{{ t.endLink }}</button>
              </div>
            </article>
          </div>
        </section>
        <p class="analytics-note">{{ t.schoolStatsNote }}</p>
      </template>
    </section>

    <section v-else-if="view === 'calendar'" :class="['page', 'calendar-page', { 'billing-read-only': billingReadOnly }]">
      <section v-if="showSetupGuide" :class="['setup-guide', { complete: setupComplete }]">
        <div class="setup-guide-intro"><small>IKARS INSTRUCTOR</small><h2>{{ setupComplete ? t.setupDone : t.setupTitle }}</h2><p v-if="!setupComplete">{{ t.setupText }}</p></div>
        <div class="setup-steps"><article v-for="(step, index) in setupSteps" :key="step.key" :class="{ ready: step.ready }"><b>{{ step.ready ? '✓' : index + 1 }}</b><span><strong>{{ step.title }}</strong><small>{{ step.help }}</small></span></article></div>
        <button v-if="setupComplete" type="button" class="primary" @click="onboardingDismissed = true">{{ t.setupClose }}</button><button v-else type="button" class="primary" @click="openAccount">{{ t.setupOpen }}</button>
      </section>
      <div :class="['page-head', 'calendar-title', `title-${busyColorMode}`]"><h1>{{ activeDayTitle }}</h1></div>
      <section :class="['week-panel', `free-${freeColorMode}`, `busy-${busyColorMode}`]">
        <div class="week-toolbar"><button :aria-label="t.previousWeek" @click="changeWeek(-1)">‹</button><div><span>{{ weekRange }}</span></div><button :aria-label="t.nextWeek" @click="changeWeek(1)">›</button><button class="today-button" @click="resetWeek">{{ t.today }}</button><button class="day-block-button" :title="activeDayBlocked ? t.unblockDay : t.blockDay" :aria-label="activeDayBlocked ? t.unblockDay : t.blockDay" @click="toggleActiveDayBlock">{{ activeDayBlocked ? '🔓' : '⊘' }}</button></div>
        <div ref="calendarScroll" class="calendar-scroll"><div class="availability-grid main-availability-grid" :style="{ gridTemplateColumns: mainGridColumns }">
          <span class="grid-corner"></span>
          <button v-for="(day, index) in weekDays" :key="'head-' + day.iso" :class="['grid-day', { active: activeDayIndex === index, weekend: day.weekend, disabled: !dayEnabled(index) }]" @click="activeDayIndex = index">{{ day.label }}<b>{{ day.number }}</b></button>
          <template v-for="time in visibleTimeSlots" :key="time">
            <time>{{ time }}</time>
            <button v-for="(day, index) in weekDays" :key="day.iso + time" :class="['status-cell', dayEnabled(index) ? (slotIsFree(day.iso, time) ? 'free-cell' : 'busy-cell') : 'locked-cell', { active: activeDayIndex === index, blocked: blockFor(day.iso, time) }]" :aria-label="`${day.label} ${day.number}, ${time}: ${dayEnabled(index) ? (blockFor(day.iso, time) ? t.blocked : (slotIsFree(day.iso, time) ? t.available : t.full)) : t.dayOff}`" @click="activeDayIndex = index">
              <template v-if="activeDayIndex === index"><span v-if="!dayEnabled(index)" class="active-day-off"><time>{{ time }}</time> · {{ t.dayOff }}</span><span v-else-if="blockFor(day.iso, time)" class="active-blocked"><span><time>{{ time }}</time> · {{ t.blocked }}</span><b @click.stop="toggleSlotBlock(day.iso, time)" :title="t.unblockSlot">×</b></span><div v-else-if="lessonFor(day.iso, time)" class="active-lesson" @click.stop="openLesson(time, lessonFor(day.iso, time))"><strong><time>{{ time }}</time> · {{ lessonFor(day.iso, time).student }}</strong><span>{{ lessonFor(day.iso, time).vehicle }} · €{{ lessonFor(day.iso, time).price }}</span><small>{{ lessonFor(day.iso, time).point }} · {{ lessonFor(day.iso, time).end }}</small><div class="lesson-badges"><em v-if="lessonFor(day.iso, time).status && lessonFor(day.iso, time).status !== 'planned'">{{ t[lessonFor(day.iso, time).status === 'no_show' ? 'noShow' : lessonFor(day.iso, time).status] }}</em><em v-if="lessonFor(day.iso, time).paymentStatus === 'paid'" class="paid-badge">{{ t.paidStatus }}</em></div></div><span v-else class="active-free"><span @click.stop="openLesson(time)"><time>{{ time }}</time> · {{ t.free }}</span><b class="add-lesson" @click.stop="openLesson(time)">+</b><b class="block-slot" @click.stop="toggleSlotBlock(day.iso, time)" :title="t.blockSlot">⊘</b></span></template>
            </button>
          </template>
        </div></div>
        <p class="week-hint">{{ t.chooseDay }}</p>
      </section>
    </section>

    <section v-else-if="view === 'students'" class="page">
      <div class="page-head"><div><small>INSTRUCTOR BASIC</small><h1>{{ t.students }}</h1></div><button class="primary" @click="openNewStudent">+ {{ t.student }}</button></div>
      <div class="student-search"><input v-model="studentSearch" :placeholder="t.searchStudent" type="search"></div>
      <div class="student-list"><article v-for="studentItem in filteredStudents" :key="studentItem.id" class="student-card" @click="openStudent(studentItem)"><div class="student-avatar">{{ studentItem.firstName[0] }}{{ studentItem.lastName[0] }}</div><div><h2>{{ studentItem.firstName }} {{ studentItem.lastName }}</h2><p>{{ studentItem.phone }} · {{ studentItem.school }}</p><span>{{ studentItem.transmission }} · €{{ studentItem.price }} · {{ studentItem.lessons }} {{ t.lessonsCount.toLowerCase() }}</span></div><div class="student-card-side"><span :class="['student-status', studentItem.status]">{{ studentItem.status === 'active' ? t.activeStatus : t.pausedStatus }}</span><button @click.stop="trackStudentCall(studentItem)">☎</button></div></article></div>
    </section>

    <section v-else-if="view === 'directory'" :class="['page', `widget-theme-${widgetTheme}`, { 'widget-page': publicWidgetMode, 'widget-banner': publicWidgetMode && widgetLayout === 'banner', 'widget-compact': publicWidgetMode && widgetLayout === 'compact', 'widget-full': publicWidgetMode && widgetLayout === 'full' }]" :style="widgetThemeStyle">
      <div v-if="publicWidgetMode && widgetLayout === 'banner' && widgetSchool" class="widget-banner-card"><div><small>{{ widgetSchool.name }}</small><h1>{{ t.bannerTitle }}</h1><p>{{ t.bannerText }}</p></div><a :href="widgetCatalogUrl" target="_top">{{ t.openInstructorList }} →</a></div>
      <a v-if="publicWidgetMode && widgetLayout !== 'banner' && widgetReturnUrl" class="widget-return" :href="widgetReturnUrl">← {{ widgetReturnLabel }}</a>
      <div v-if="publicWidgetMode && widgetLayout !== 'banner'" class="widget-head"><img v-if="widgetSchool?.logoUrl" :src="widgetSchool.logoUrl" :alt="widgetSchool.name"><div><small>{{ widgetSchool?.name || 'IKARS.LV' }}</small><h1>{{ t.schoolWidget }}</h1></div><button type="button" @click="language = language === 'LV' ? 'RU' : 'LV'">{{ language }}</button></div>
      <div v-else-if="!publicWidgetMode" class="page-head"><div><small>IKARS.LV</small><h1>{{ t.directory }}</h1></div></div>
      <p v-if="publicWidgetMode && !widgetSchool" class="analytics-note">{{ t.schoolNotFound }}</p>
      <div v-if="!publicWidgetMode || widgetLayout !== 'banner'" class="service-choice"><span>{{ t.chooseService }}</span><div><button :class="{ active: serviceType === 'lesson' }" @click="serviceType = 'lesson'">{{ t.lesson }}</button><button :class="{ active: serviceType === 'exam' }" @click="serviceType = 'exam'">{{ t.exam }}</button></div></div>
      <div v-if="!publicWidgetMode || widgetLayout !== 'banner'" class="filters"><select v-model="transmission"><option value="ALL">Manual + Automatic</option><option value="M">Manual</option><option value="A">Automatic</option></select><select v-model="vehicleMake"><option value="ALL">{{ t.allVehicleMakes }}</option><option v-for="make in vehicleMakes" :key="make" :value="make">{{ make }}</option></select><select v-model="district"><option value="ALL">{{ t.allRiga }}</option><option>Centrs</option><option>Purvciems</option><option>Imanta</option><option>Teika</option></select></div>
      <div v-if="!publicWidgetMode || widgetLayout !== 'banner'" class="cards">
        <p v-if="!filteredInstructors.length" class="analytics-note">{{ t.publicEmpty }}</p>
        <article v-for="instructor in filteredInstructors" :key="instructor.id" class="instructor" @click="openProfile(instructor)">
          <button v-if="instructor.photoUrl && widgetShowPhotos" type="button" class="instructor-photo-button" :aria-label="instructor.name" @click.stop="openPhoto(instructor)"><img class="avatar instructor-photo" :src="instructor.photoUrl" :alt="instructor.name"></button>
          <div v-else class="avatar">{{ instructor.name.split(' ').map((part) => part[0]).join('') }}</div>
          <div class="instructor-main"><div class="instructor-title"><h2>{{ instructor.name }}</h2><div v-if="instructor.phone" class="instructor-phone"><a :href="`tel:${instructor.phone}`" @click.stop.prevent="trackCall(instructor)">{{ instructor.phone }}</a><button class="quick-call" :aria-label="t.call" @click.stop="trackCall(instructor)">☎ <span>{{ language === 'LV' ? 'Zvanīt' : 'Позвонить' }}</span></button></div></div><p>{{ instructor.languages.map((item) => item.toUpperCase()).join(' · ') }} · {{ instructor.categories.join(', ') }}</p><p>{{ instructor.meetingPoints.join(' / ') }}</p><div class="vehicles"><span v-for="vehicle in visibleVehicles(instructor)" :key="vehicle.id">{{ vehicle.transmission }} · {{ vehicle.name }} · €{{ vehicle.price }}</span></div><strong>{{ t.nearestFive }}:</strong><div class="availability-list"><span v-for="slot in instructor.availability.slice(0, 3)" :key="slot.date + slot.time">{{ formatAvailability(slot) }}</span></div><button class="calendar-link" @click.stop="openAvailability(instructor)">▦ {{ t.showCalendar }}</button></div>
        </article>
      </div>
      <footer v-if="publicWidgetMode && widgetLayout !== 'banner'" class="widget-credit">{{ t.poweredBy }}</footer>
    </section>

    <div v-if="enlargedPhoto" class="photo-lightbox" role="dialog" aria-modal="true" :aria-label="enlargedPhoto.name" @click.self="closePhoto"><figure><button type="button" :aria-label="t.close" @click="closePhoto">×</button><img :src="enlargedPhoto.photoUrl" :alt="enlargedPhoto.name"><figcaption>{{ enlargedPhoto.name }}</figcaption></figure></div>

    <section v-if="!publicDirectoryMode && !schoolDashboardMode && view === 'statistics'" class="page"><div class="page-head"><div><small>{{ t.lastDays }}</small><h1>{{ t.statistics }}</h1></div></div><div class="stats"><article><span>{{ t.profiles }}</span><strong>{{ analytics.profileViews }}</strong></article><article><span>{{ t.calls }}</span><strong>{{ analytics.phoneClicks }}</strong></article><article><span>{{ t.catalogCalls }}</span><strong>{{ analytics.catalogPhoneClicks }}</strong></article><article><span>{{ t.widgetCalls }}</span><strong>{{ analytics.widgetPhoneClicks }}</strong></article></div><p class="analytics-note">{{ t.instructorStatsNote }}</p></section>

    <div v-if="lessonDialog" class="modal" @click.self="lessonDialog = false">
      <form class="lesson-form" @submit.prevent="saveLesson">
        <div class="modal-head"><h2>{{ t.lesson }} · {{ lessonDateTitle(lessonForm.date) }}</h2><button type="button" @click="lessonDialog = false">×</button></div>
        <label class="student-picker">{{ t.student }}
          <input v-model="lessonForm.student" maxlength="120" autocomplete="off" autofocus @input="handleLessonStudentInput">
          <span v-if="lessonStudentSuggestions.length" class="student-suggestions">
            <button v-for="student in lessonStudentSuggestions" :key="student.id" type="button" @click="selectLessonStudent(student)"><b>{{ student.firstName }} {{ student.lastName }}</b><small>{{ student.phone || student.school || '—' }}</small></button>
          </span>
        </label>
        <label class="app-date-field">{{ t.lessonDate }}
          <button type="button" class="date-picker-trigger" @click="openDatePicker">{{ lessonDateTitle(lessonForm.date) }} <span>▾</span></button>
          <section v-if="datePickerOpen" class="app-date-picker">
            <header><button type="button" :aria-label="t.previousWeek" @click="changeDatePickerMonth(-1)">‹</button><b>{{ datePickerTitle }}</b><button type="button" :aria-label="t.nextWeek" @click="changeDatePickerMonth(1)">›</button></header>
            <div class="date-picker-weekdays"><span v-for="day in datePickerWeekdays" :key="day">{{ day }}</span></div>
            <div class="date-picker-days"><button v-for="day in datePickerDays" :key="day.iso" type="button" :class="{ muted: !day.currentMonth, selected: day.iso === lessonForm.date }" @click="selectLessonDate(day)">{{ day.number }}</button></div>
          </section>
        </label>
        <div class="form-grid"><label>{{ t.start }}<select v-model="lessonForm.time"><option v-for="time in timeSlots" :key="time">{{ time }}</option></select></label><label>{{ t.duration }}<select v-model.number="lessonForm.duration"><option :value="60">60 min</option><option :value="90">90 min</option></select></label></div>
        <label>{{ t.vehicle }}<select v-model="lessonForm.vehicleId" @change="selectVehicle"><option v-for="vehicle in currentInstructor.vehicles" :key="vehicle.id" :value="vehicle.id">{{ vehicle.transmission }} · {{ vehicle.name }}</option></select></label>
        <div class="form-grid"><label>{{ t.price }}<input v-model.number="lessonForm.price" type="number" min="0" step="1"></label><label>{{ t.meeting }}<select v-model="lessonForm.point"><option v-for="point in currentInstructor.meetingPoints" :key="point.id || point" :value="point.label || point">{{ point.label || point }}</option></select></label></div>
        <label>{{ t.lessonNote }}<input v-model="lessonForm.note" maxlength="160" :placeholder="language === 'LV' ? 'Piem., parkošanās, pirms eksāmena' : 'Например: парковка, перед экзаменом'"></label>
        <div class="lesson-result"><label>{{ t.lessonStatus }}<select v-model="lessonForm.status" @change="changeLessonStatus"><option value="planned">{{ t.planned }}</option><option value="completed">{{ t.completed }}</option><option value="cancelled">{{ t.cancelled }}</option><option value="no_show">{{ t.noShow }}</option></select></label><label class="chargeable-check"><input v-model="lessonForm.chargeable" type="checkbox"> <span>{{ t.chargeable }}</span></label><p v-if="lessonForm.status === 'no_show'" class="rule-note">{{ t.noShowRule }}</p><div class="form-grid"><label>{{ t.payment }}<select v-model="lessonForm.paymentStatus"><option value="unpaid">{{ t.unpaid }}</option><option value="paid">{{ t.paidStatus }}</option></select></label><label>{{ t.paymentMethod }}<select v-model="lessonForm.paymentMethod"><option value="cash">{{ t.cash }}</option><option value="transfer">{{ t.transfer }}</option><option value="school">{{ t.schoolPayment }}</option><option value="advance">{{ t.advance }}</option></select></label></div><small v-if="lessonForm.paymentStatus === 'paid' && lessonForm.paymentMethod === 'advance'" class="advance-balance-hint">{{ t.availableAdvance }}: €{{ Number(studentRecords.find(item => item.id === lessonForm.studentId)?.advanceBalance || 0).toFixed(2) }}</small></div>
        <p v-if="lessonError" class="form-error">{{ lessonError }}</p><div class="form-actions"><button type="button" @click="lessonDialog = false">{{ t.cancel }}</button><button class="primary">{{ t.save }}</button></div>
      </form>
    </div>

    <div v-if="studentDialog && studentForm" class="modal" @click.self="studentDialog = false"><form class="lesson-form student-form" @submit.prevent="saveStudent"><div class="modal-head"><h2>{{ studentForm.firstName || t.student }} {{ studentForm.lastName }}</h2><button type="button" @click="studentDialog = false">×</button></div><div class="form-grid"><label>{{ t.student }}<input v-model="studentForm.firstName" required></label><label>&nbsp;<input v-model="studentForm.lastName" required></label></div><div class="form-grid"><label>{{ t.phone }}<input v-model="studentForm.phone" type="tel"></label><label>{{ t.email }}<input v-model="studentForm.email" type="email"></label></div><label>{{ t.school }}<input v-model="studentForm.school"></label><div class="form-grid"><label>{{ t.vehicle }}<select v-model="studentForm.vehicleId"><option v-for="vehicle in currentInstructor.vehicles" :key="vehicle.id" :value="vehicle.id">{{ vehicle.transmission }} · {{ vehicle.name }}</option></select></label><label>{{ t.price }}<input v-model.number="studentForm.price" type="number" min="0"></label></div><label>{{ t.status }}<select v-model="studentForm.status"><option value="active">{{ t.activeStatus }}</option><option value="paused">{{ t.pausedStatus }}</option></select></label><label>{{ t.notes }}<textarea v-model="studentForm.notes" rows="3"></textarea></label><div class="student-finance"><button type="button" class="lessons-summary" @click="studentLessonsVisible = !studentLessonsVisible"><span>{{ t.lessonsCount }}</span><b>{{ selectedStudentLessons.length }}</b><small>›</small></button><div><span>{{ t.chargedTotal }}</span><b>€{{ selectedStudentFinance.charged }}</b></div><div><span>{{ t.paid }}</span><b>€{{ selectedStudentFinance.paid }}</b></div><div :class="{ 'finance-debt': selectedStudentFinance.debt > 0 }"><span>{{ t.debt }}</span><b>€{{ selectedStudentFinance.debt }}</b></div><div v-if="selectedStudentFinance.credit > 0" class="finance-credit"><span>{{ t.credit }}</span><b>€{{ selectedStudentFinance.credit }}</b></div></div><section v-if="studentLessonsVisible" class="lesson-history"><h3>{{ t.lessonHistory }}</h3><p v-if="!selectedStudentLessons.length">{{ t.noLessons }}</p><button v-for="(item, index) in selectedStudentLessons" :key="item.id" type="button" class="lesson-history-item" @click="openStudentLesson(item)"><b>{{ index + 1 }}. {{ new Date(item.date + 'T12:00:00').toLocaleDateString(t.locale) }} · {{ item.time }}</b><span>{{ t[item.status === 'no_show' ? 'noShow' : item.status] }} · €{{ item.price }}</span><small>{{ item.vehicle }} · {{ item.point }}</small><small>{{ item.paymentStatus === 'paid' ? t.paidStatus : t.unpaid }}<template v-if="item.paymentStatus === 'paid'"> · {{ t[item.paymentMethod === 'school' ? 'schoolPayment' : item.paymentMethod] }}</template> · {{ item.note || '—' }}</small><em>{{ t.editLesson }} ›</em></button></section><div class="form-actions"><button type="button" @click="studentDialog = false">{{ t.cancel }}</button><button class="primary">{{ t.save }}</button></div></form></div>

    <div v-if="accountDialog && profileForm" class="modal account-modal" @click.self="accountDialog = false">
      <section class="account-form">
        <div class="modal-head"><div><small>INSTRUCTOR BASIC</small><h2>{{ t.account }}</h2></div><button type="button" @click="accountDialog = false">×</button></div>
        <p v-if="accountMessage" :class="['account-message', 'account-message-top', { error: accountMessage === t.saveError }]" role="status" aria-live="polite">{{ accountMessage }}</p>

        <section :class="['account-section', 'backup-section', { due: backupReminderDue }]">
          <div><h3>{{ t.dataBackup }}</h3><p v-if="backupReminderDue">{{ t.backupReminder }}</p><small>{{ t.lastBackup }}: {{ lastCalendarExport ? new Date(lastCalendarExport).toLocaleDateString(t.locale) : t.neverExported }}</small></div>
          <div class="backup-range"><label>{{ t.exportFrom }}<input v-model="exportDateFrom" type="date"></label><label>{{ t.exportTo }}<input v-model="exportDateTo" type="date"></label></div>
          <button type="button" class="primary" @click="exportCalendarXls">↓ {{ t.downloadCalendar }}</button>
        </section>

        <form class="account-section" @submit.prevent="saveProfileSettings">
          <h3>{{ t.profileData }}</h3>
          <div class="profile-photo-editor"><img v-if="profileForm.photoUrl" :src="profileForm.photoUrl" :alt="`${profileForm.firstName} ${profileForm.lastName}`"><div v-else class="profile-photo-placeholder">{{ (profileForm.firstName?.[0] || '') + (profileForm.lastName?.[0] || '') }}</div><div><b>{{ t.profilePhoto }}</b><p>{{ t.photoHelp }}</p><input ref="photoInput" class="visually-hidden" type="file" accept="image/jpeg,image/png,image/webp" @change="prepareProfilePhoto"><div class="profile-photo-actions"><button type="button" class="secondary-action" :disabled="accountBusy" @click="photoInput?.click()">{{ t.choosePhoto }}</button><button v-if="profileForm.photoUrl" type="button" class="photo-delete-action" :disabled="accountBusy" @click="deleteProfilePhoto">{{ t.deletePhoto }}</button></div></div></div>
          <div class="form-grid"><label>{{ t.firstName }}<input v-model="profileForm.firstName" required></label><label>{{ t.lastName }}<input v-model="profileForm.lastName" required></label></div>
          <label>{{ t.phone }}<input v-model="profileForm.phone" type="tel"></label>
          <div class="profile-options"><fieldset><legend>{{ t.teachingLanguages }}</legend><label class="day-toggle"><input v-model="profileForm.languages" type="checkbox" value="lv"><span>Latviešu</span></label><label class="day-toggle"><input v-model="profileForm.languages" type="checkbox" value="ru"><span>Русский</span></label></fieldset><fieldset><legend>{{ t.drivingCategories }}</legend><label v-for="category in ['A','B','BE','C','CE','D']" :key="category" class="day-toggle"><input v-model="profileForm.categories" type="checkbox" :value="category"><span>{{ category }}</span></label></fieldset></div>
          <div class="calendar-day-settings"><label class="day-toggle"><input v-model="profileForm.isPublic" type="checkbox"><span>{{ t.publishProfile }}</span></label><label class="day-toggle"><input v-model="profileForm.publicPhone" type="checkbox"><span>{{ t.publishPhone }}</span></label></div>
          <button class="primary" :disabled="accountBusy">{{ t.save }}</button>
        </form>

        <section class="account-section calendar-preferences">
          <h3>{{ t.calendarPreferences }}</h3>
          <div class="calendar-preferences-grid">
            <label>{{ t.standardDuration }}<select v-model.number="slotMinutes"><option :value="90">90 {{ t.minutesShort }}</option><option :value="60">60 {{ t.minutesShort }}</option></select></label>
            <label>{{ t.firstLesson }}<select v-model="workStart" @change="normalizeWorkRange"><option v-for="time in scheduleBoundarySlots" :key="'start-' + time">{{ time }}</option></select></label>
            <label>{{ t.lastLesson }}<select v-model="workEnd"><option v-for="time in availableEndSlots" :key="'end-' + time">{{ time }}</option></select></label>
            <label>{{ t.freeStyle }}<select v-model="freeColorMode"><option value="outline">{{ t.outline }}</option><option value="mint">{{ t.mint }}</option></select></label>
            <label>{{ t.busyStyle }}<select v-model="busyColorMode"><option value="cool">{{ t.cool }}</option><option value="warm">{{ t.warm }}</option><option value="pistachio">{{ t.pistachio }}</option><option value="canary">{{ t.canary }}</option><option value="peach">{{ t.peach }}</option></select></label>
          </div>
          <div class="calendar-day-settings"><label class="day-toggle"><input v-model="saturdayEnabled" type="checkbox"><span>{{ t.saturday }}</span></label><label class="day-toggle"><input v-model="sundayEnabled" type="checkbox"><span>{{ t.sunday }}</span></label></div>
          <button class="primary" type="button" :disabled="accountBusy" @click="saveCalendarPreferences">{{ t.save }}</button>
        </section>

        <section class="account-section">
          <div class="account-section-title"><h3>{{ t.cars }}</h3><button type="button" class="secondary-action" @click="resetVehicleForm">+ {{ t.newCar }}</button></div>
          <div v-if="currentInstructor.vehicles.length" class="account-items">
            <button v-for="vehicle in currentInstructor.vehicles" :key="vehicle.id" type="button" @click="editVehicle(vehicle)"><span><b>{{ vehicle.transmission }} · {{ vehicle.name }}</b><small>€{{ vehicle.price }} · {{ vehicle.registrationNumber || '—' }}</small></span><em>{{ t.edit }}</em></button>
          </div>
          <form @submit.prevent="saveVehicleSettings">
            <h4>{{ vehicleForm.id ? t.editCarForm : t.newCarForm }}</h4>
            <div class="form-grid"><label>{{ t.make }}<input v-model="vehicleForm.make" required></label><label>{{ t.model }}<input v-model="vehicleForm.model" required></label></div>
            <div class="form-grid"><label>{{ t.year }}<input v-model.number="vehicleForm.year" type="number" min="1980" :max="new Date().getFullYear() + 1"></label><label>{{ t.vehicle }}<select v-model="vehicleForm.transmission"><option value="M">{{ t.manual }}</option><option value="A">{{ t.automatic }}</option></select></label></div>
            <div class="form-grid"><label>{{ t.standardPrice }}<input v-model.number="vehicleForm.price" type="number" min="0" step="1" required></label><label>{{ t.weekendPrice }}<input v-model.number="vehicleForm.weekendPrice" type="number" min="0" step="1"></label></div>
            <label>{{ t.registrationNumber }}<input v-model="vehicleForm.registrationNumber"></label>
            <button class="primary" :disabled="accountBusy">{{ t.addCar }}</button>
          </form>
        </section>

        <section class="account-section">
          <h3>{{ t.points }}</h3>
          <div v-if="currentInstructor.meetingPoints.length" class="account-items meeting-point-items">
            <article v-for="point in currentInstructor.meetingPoints" :key="point.id"><button type="button" class="meeting-point-main" @click="editMeetingPoint(point)"><span><b>{{ point.label }}</b><small>{{ point.city }} · €{{ point.surcharge }}</small></span><em>{{ t.edit }}</em></button><div><button type="button" :class="['point-public', { active: point.showInWidget }]" @click="selectPublicMeetingPoint(point)">{{ point.showInWidget ? '✓ ' : '' }}{{ t.widgetLocation }}</button><button type="button" class="point-delete" @click="archiveMeetingPoint(point)">{{ t.deleteLocation }}</button></div></article>
          </div>
          <form @submit.prevent="saveMeetingPointSettings">
            <div class="form-grid"><label>{{ t.city }}<input v-model="meetingPointForm.city" required></label><label>{{ t.districtName }}<input v-model="meetingPointForm.district"></label></div>
            <label>{{ t.publicName }}<input v-model="meetingPointForm.name" required></label>
            <div class="form-grid"><label>{{ t.surcharge }}<input v-model.number="meetingPointForm.surcharge" type="number" min="0" step="1"></label><label>{{ t.directions }}<input v-model="meetingPointForm.directions"></label></div>
            <button class="primary" :disabled="accountBusy">{{ t.addPoint }}</button>
          </form>
        </section>

        <section v-if="schoolInvitations.length" class="account-section school-invitations">
          <h3>{{ t.schoolInvitations }}</h3>
          <article v-for="invitation in schoolInvitations" :key="invitation.linkId">
            <div><strong>{{ invitation.schoolName }}</strong><span>{{ t.invitationText }}</span></div>
            <div><button type="button" :disabled="accountBusy" @click="respondToSchoolInvitation(invitation, 'decline')">{{ t.declineInvitation }}</button><button type="button" class="primary" :disabled="accountBusy" @click="respondToSchoolInvitation(invitation, 'accept')">{{ t.acceptInvitation }}</button></div>
          </article>
        </section>

        <button class="close-account" type="button" @click="accountDialog = false">{{ t.close }}</button>
      </section>
    </div>

    <div v-if="availabilityDialog && availabilityInstructor" class="modal" @click.self="availabilityDialog = false"><section class="availability-modal"><div class="modal-head"><div><small>{{ t.availableTimes }}</small><h2>{{ availabilityInstructor.name }}</h2></div><button type="button" @click="availabilityDialog = false">×</button></div><div class="directory-calendar-toolbar"><button :aria-label="t.previousWeek" @click="changeWeek(-1)">‹</button><b>{{ weekRange }}</b><button :aria-label="t.nextWeek" @click="changeWeek(1)">›</button></div><div ref="publicCalendarScroll" class="mini-week"><div class="availability-grid instructor-availability-grid"><span class="grid-corner"></span><span v-for="day in weekDays" :key="'head-' + day.iso" class="grid-day">{{ day.label }}<b>{{ day.number }}</b></span><template v-for="time in timeSlots" :key="time"><time>{{ time }}</time><span v-for="day in weekDays" :key="day.iso + time" :class="['status-cell', instructorSlotIsFree(availabilityInstructor, day.date, time) ? 'free-cell' : 'busy-cell']" :title="instructorSlotIsFree(availabilityInstructor, day.date, time) ? t.available : t.full"><small v-if="instructorSlotIsFree(availabilityInstructor, day.date, time)" class="public-free-label">{{ t.available }}</small></span></template></div></div><button class="primary close-modal" @click="availabilityDialog = false">{{ t.close }}</button></section></div>
  </main>
  <Teleport v-if="studentDialog && studentForm?.id" defer to=".student-form"><section class="student-personal-access"><h3>IKARS · STUDENT</h3><p>{{ t.personalSchedule }}</p><div class="student-link-actions"><button type="button" class="secondary" :disabled="studentScheduleBusy" @click="createPersonalStudentLink">{{ studentScheduleLink ? t.replaceStudentLink : t.createStudentLink }}</button><button v-if="studentScheduleLink" type="button" class="secondary" @click="copyPersonalStudentLink">{{ t.copyStudentLink }}</button><button type="button" class="secondary danger" :disabled="studentScheduleBusy" @click="revokePersonalStudentLink">{{ t.revokeStudentLink }}</button></div><input v-if="studentScheduleLink" :value="studentScheduleLink" readonly @focus="$event.target.select()"><small v-if="studentScheduleMessage" role="status">{{ studentScheduleMessage }}</small></section></Teleport>
  <Teleport v-if="studentDialog && studentForm?.id" defer to=".student-form"><fieldset class="student-visibility-options"><legend>{{ t.studentVisibility }}</legend><label><input v-model="studentScheduleShowFullHistory" type="radio" :value="true" @change="saveStudentScheduleVisibility"><span><b>{{ t.studentFullView }}</b><small>{{ t.studentFullViewHelp }}</small></span></label><label><input v-model="studentScheduleShowFullHistory" type="radio" :value="false" @change="saveStudentScheduleVisibility"><span><b>{{ t.studentBalanceView }}</b><small>{{ t.studentBalanceViewHelp }}</small></span></label></fieldset></Teleport>
  <Teleport v-if="studentDialog && studentForm?.id" defer to=".student-form"><section class="student-advance"><div class="student-advance-head"><div><h3>{{ t.studentAdvance }}</h3><small>{{ t.availableAdvance }}</small></div><strong>€{{ Number(studentForm.advanceBalance || 0).toFixed(2) }}</strong></div><form class="advance-entry" @submit.prevent="recordStudentAdvance"><label>{{ t.advanceAmount }}<input v-model.number="studentAdvanceForm.amount" type="number" min="0.01" step="0.01" required></label><label>{{ t.paymentMethod }}<select v-model="studentAdvanceForm.method"><option value="cash">{{ t.cash }}</option><option value="transfer">{{ t.transfer }}</option><option value="school">{{ t.schoolPayment }}</option></select></label><label>{{ t.date }}<input v-model="studentAdvanceForm.paidAt" type="date" required></label><label>{{ t.notes }}<input v-model="studentAdvanceForm.note"></label><button class="primary" :disabled="studentAdvanceBusy">{{ t.recordAdvance }}</button></form><small v-if="studentAdvanceMessage" role="status">{{ studentAdvanceMessage }}</small><details v-if="studentForm.advancePayments?.length"><summary>{{ t.advanceHistory }} ({{ studentForm.advancePayments.length }})</summary><article v-for="payment in studentForm.advancePayments" :key="payment.id" class="advance-payment"><span><b>€{{ Number(payment.amount).toFixed(2) }}</b><small>{{ new Date(payment.paid_at).toLocaleDateString(t.locale) }} · {{ t[payment.method === 'school' ? 'schoolPayment' : payment.method] }}</small></span><button type="button" class="danger" :disabled="studentAdvanceBusy" @click="voidStudentAdvance(payment)">{{ t.voidAdvance }}</button></article></details></section></Teleport>
</template>
