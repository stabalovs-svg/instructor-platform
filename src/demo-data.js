export const instructors = [
  {
    id: 'andris-berzins', name: 'Andris Bērziņš', school: 'Partneru autoskola',
    languages: ['LV', 'RU'], categories: ['B'], phone: '+37120000001',
    meetingPoints: ['Centrs — Stacijas laukums', 'Purvciems — Dzelzavas iela'],
    vehicles: [
      { id: 'golf', name: 'Volkswagen Golf', transmission: 'M', price: 35 },
      { id: 'corolla', name: 'Toyota Corolla', transmission: 'A', price: 40 },
    ],
    availability: [
      { date: '2026-08-10', time: '12:00' }, { date: '2026-08-11', time: '18:00' },
      { date: '2026-08-13', time: '09:00' }, { date: '2026-08-14', time: '16:30' },
      { date: '2026-08-18', time: '19:30' }, { date: '2026-08-20', time: '10:30' },
    ],
  },
  {
    id: 'ilze-kalnina', name: 'Ilze Kalniņa', school: 'Partneru autoskola',
    languages: ['LV', 'EN'], categories: ['B'], phone: '+37120000002',
    meetingPoints: ['Imanta — pie autoskolas'],
    vehicles: [{ id: 'yaris', name: 'Toyota Yaris', transmission: 'A', price: 42 }],
    availability: [
      { date: '2026-08-11', time: '09:30' }, { date: '2026-08-12', time: '13:30' },
      { date: '2026-08-14', time: '18:00' }, { date: '2026-08-17', time: '07:30' },
      { date: '2026-08-19', time: '16:30' },
    ],
  },
  {
    id: 'janis-ozols', name: 'Jānis Ozols', school: 'Partneru autoskola',
    languages: ['LV', 'RU', 'EN'], categories: ['A', 'B'], phone: '+37120000003',
    meetingPoints: ['Teika — Brīvības gatve'],
    vehicles: [{ id: 'focus', name: 'Ford Focus', transmission: 'M', price: 34 }],
    availability: [
      { date: '2026-08-12', time: '18:00' }, { date: '2026-08-13', time: '19:30' },
      { date: '2026-08-15', time: '09:00' }, { date: '2026-08-18', time: '15:00' },
      { date: '2026-08-21', time: '18:00' },
    ],
  },
]

export const lessons = [
  { id: 1, time: '07:30', end: '09:00', student: 'Laura Liepiņa', vehicle: 'M · Golf', price: 35, point: 'Centrs', status: 'completed', chargeable: true, paymentStatus: 'paid', paymentMethod: 'cash', note: 'Obligātā nodarbība pirms eksāmena.' },
  { id: 2, time: '10:30', end: '12:00', student: 'Mārtiņš Kalniņš', vehicle: 'A · Corolla', price: 40, point: 'Purvciems', status: 'no_show', chargeable: true, paymentStatus: 'unpaid', paymentMethod: 'cash', note: 'Neieradās un nebrīdināja 24 stundas iepriekš.' },
  { id: 3, time: '15:00', end: '16:30', student: 'Elīna Ozola', vehicle: 'M · Golf', price: 35, point: 'Centrs' },
]

export const timeSlots = ['06:00', '07:30', '09:00', '10:30', '12:00', '13:30', '15:00', '16:30', '18:00', '19:30', '21:00']

export const students = [
  { id: 1, firstName: 'Laura', lastName: 'Liepiņa', phone: '+371 26123456', email: 'laura.liepina@example.lv', school: 'Partneru autoskola', vehicleId: 'golf', transmission: 'M', price: 35, paid: 210, lessons: 7, status: 'active', notes: 'Vēlas nodarbības darbdienu rītos. Gatavojas CSDD eksāmenam.' },
  { id: 2, firstName: 'Mārtiņš', lastName: 'Kalniņš', phone: '+371 27112233', email: 'martins.kalnins@example.lv', school: 'Partneru autoskola', vehicleId: 'corolla', transmission: 'A', price: 40, paid: 160, lessons: 5, status: 'active', notes: 'Ērtāk satikties Purvciemā pēc 17:00.' },
  { id: 3, firstName: 'Elīna', lastName: 'Ozola', phone: '+371 29114455', email: 'elina.ozola@example.lv', school: 'Rīgas autoskola', vehicleId: 'golf', transmission: 'M', price: 35, paid: 105, lessons: 4, status: 'paused', notes: 'Mācības apturētas līdz septembrim.' },
  { id: 4, firstName: 'Rihards', lastName: 'Zariņš', phone: '+371 20334455', email: 'rihards.zarins@example.lv', school: 'Partneru autoskola', vehicleId: 'golf', transmission: 'M', price: 35, paid: 280, lessons: 8, status: 'active', notes: 'Nepieciešams vairāk trenēt parkošanos.' },
]
