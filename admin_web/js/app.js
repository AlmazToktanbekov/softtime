const API = (() => {
  const queryValue = new URLSearchParams(window.location.search).get('api');
  const storedValue = localStorage.getItem('api_base_url');
  const normalize = (value) => value ? value.replace(/\/+$/, '') : value;

  if (queryValue) {
    const normalized = normalize(queryValue);
    localStorage.setItem('api_base_url', normalized);
    return normalized;
  }

  if (storedValue) {
    return normalize(storedValue);
  }

  // http(s) на сервере — тот же host, что и у страницы (например :8000/admin/ → :8000/api/v1)
  if (window.location.protocol === 'http:' || window.location.protocol === 'https:') {
    return `${window.location.origin}/api/v1`;
  }

  // file:// — задайте ?api=... один раз или положите api_base_url в localStorage
  return 'http://localhost:8000/api/v1';
})();
let accessToken = localStorage.getItem('access_token');
let allEmployees = [];
let allAttendance = [];

async function loadWorkTimeSettings() {
  try {
    const data = await apiFetch('/settings/work-time');

    document.getElementById('workStartHour').value = data.work_start_hour;
    document.getElementById('workStartMinute').value = data.work_start_minute;
    document.getElementById('workEndHour').value = data.work_end_hour;
    document.getElementById('workEndMinute').value = data.work_end_minute;
    document.getElementById('gracePeriodMinutes').value = data.grace_period_minutes;

    document.getElementById('countEarlyArrival').checked = !!data.count_early_arrival;
    document.getElementById('countEarlyLeave').checked = !!data.count_early_leave;
    document.getElementById('countOvertime').checked = !!data.count_overtime;
  } catch (e) {
    showToast(e.message, 'error');
  }
}

let currentManualAttendanceId = null;

function openManualCheckout(attendanceId, employeeName) {
  currentManualAttendanceId = attendanceId;
  document.getElementById('manualCheckoutEmployee').value = employeeName || '';
  document.getElementById('manualCheckoutNote').value = '';

  const now = new Date();
  const local = new Date(now.getTime() - now.getTimezoneOffset() * 60000)
    .toISOString()
    .slice(0, 16);

  document.getElementById('manualCheckoutTime').value = local;

  openModal('manualCheckout');
}

async function saveManualCheckout() {
  try {
    if (!currentManualAttendanceId) {
      showToast('Не выбрана запись', 'error');
      return;
    }

    const timeValue = document.getElementById('manualCheckoutTime').value;
    const noteValue = document.getElementById('manualCheckoutNote').value;

    if (!timeValue) {
      showToast('Укажите время ухода', 'error');
      return;
    }

    const payload = {
      check_out_time: new Date(timeValue).toISOString(),
      note: noteValue || null
    };

    await apiFetch(`/attendance/${currentManualAttendanceId}/manual-checkout`, {
      method: 'PATCH',
      body: JSON.stringify(payload)
    });

    closeModal('manualCheckout');
    showToast('Уход сохранён вручную', 'success');
    loadAttendance();
    loadDashboard();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function openApprovedAbsenceModal() {
  try {
    const employees = await fetchAllUsers();
    const sel = document.getElementById('approvedAbsenceEmployeeId');
    sel.innerHTML = '<option value="">— Выберите сотрудника —</option>' +
      employees.filter(e => e.status === 'ACTIVE').map(e => `<option value="${e.id}">${e.full_name} (${e.team_name || '—'})</option>`).join('');
    document.getElementById('approvedAbsenceDate').value = new Date().toISOString().slice(0, 10);
    document.getElementById('approvedAbsenceNote').value = '';
    openModal('approvedAbsence');
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function saveApprovedAbsence() {
  try {
    const employeeId = document.getElementById('approvedAbsenceEmployeeId').value;
    const dateVal = document.getElementById('approvedAbsenceDate').value;
    const note = document.getElementById('approvedAbsenceNote').value?.trim();

    if (!employeeId) {
      showToast('Выберите сотрудника', 'error');
      return;
    }
    if (!dateVal) {
      showToast('Укажите дату', 'error');
      return;
    }
    if (!note) {
      showToast('Укажите комментарий (причину отсутствия)', 'error');
      return;
    }

    await apiFetch('/attendance/approved-absence', {
      method: 'POST',
      body: JSON.stringify({ user_id: employeeId, date: dateVal, note })
    });

    closeModal('approvedAbsence');
    showToast('Разрешённое отсутствие сохранено', 'success');
    loadAttendance();
    loadDashboard();
    if (typeof loadReports === 'function' && document.getElementById('page-reports')?.classList.contains('active')) loadReports();
  } catch (e) {
    showToast(e.message || e.detail || 'Ошибка', 'error');
  }
}



async function saveWorkTimeSettings() {
  try {
    const payload = {
      work_start_hour: Number(document.getElementById('workStartHour').value),
      work_start_minute: Number(document.getElementById('workStartMinute').value),
      work_end_hour: Number(document.getElementById('workEndHour').value),
      work_end_minute: Number(document.getElementById('workEndMinute').value),
      grace_period_minutes: Number(document.getElementById('gracePeriodMinutes').value),
      count_early_arrival: document.getElementById('countEarlyArrival').checked,
      count_early_leave: document.getElementById('countEarlyLeave').checked,
      count_overtime: document.getElementById('countOvertime').checked
    };

    await apiFetch('/settings/work-time', {
      method: 'PUT',
      body: JSON.stringify(payload)
    });

    showToast('Настройки рабочего времени сохранены', 'success');
    loadWorkTimeSettings();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

// =========== AUTH ===========
async function doLogin() {
  const u = document.getElementById('loginUsername').value;
  const p = document.getElementById('loginPassword').value;
  try {
    const r = await fetch(`${API}/auth/login`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: u, password: p })
    });
    const d = await r.json();
    if (!r.ok) throw new Error(d.detail || 'Ошибка');
    accessToken = d.access_token;
    localStorage.setItem('access_token', accessToken);
    localStorage.setItem('refresh_token', d.refresh_token);
    document.getElementById('loginPage').style.display = 'none';
    initApp();
    showMobileHeader(u);
  } catch (e) {
    const el = document.getElementById('loginError');
    el.style.display = 'block';
    el.textContent = e.message;
  }
}

async function doLogout() {
  localStorage.clear();
  location.reload();
}

function formatApiDetail(d) {
  if (!d || d.detail == null) return 'API Error';
  if (typeof d.detail === 'string') return d.detail;
  if (Array.isArray(d.detail)) {
    return d.detail.map(x => (x && x.msg) ? x.msg : JSON.stringify(x)).join('; ');
  }
  return 'API Error';
}

/** GET /users with pagination until all items are loaded (API returns PaginatedUsers). */
async function fetchAllUsers(query = {}) {
  const limit = 100;
  let page = 1;
  const all = [];
  while (true) {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    for (const [k, v] of Object.entries(query)) {
      if (v != null && v !== '') params.set(k, String(v));
    }
    const data = await apiFetch(`/users?${params}`);
    if (!data || !Array.isArray(data.items)) break;
    all.push(...data.items);
    if (data.items.length < limit) break;
    if (typeof data.total === 'number' && all.length >= data.total) break;
    page++;
  }
  return all;
}

async function apiFetch(url, opts = {}) {
  opts.headers = { ...(opts.headers || {}), 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' };
  let r = await fetch(API + url, opts);
  if (r.status === 401) {
    const ok = await tryRefresh();
    if (ok) {
      opts.headers['Authorization'] = `Bearer ${accessToken}`;
      r = await fetch(API + url, opts);
    } else { doLogout(); return null; }
  }
  if (!r.ok) {
    const d = await r.json().catch(() => ({}));
    throw new Error(formatApiDetail(d));
  }
  if (r.status === 204 || r.status === 205) return null;
  const txt = await r.text();
  if (!txt) return null;
  try { return JSON.parse(txt); } catch { return null; }
}

async function tryRefresh() {
  const rt = localStorage.getItem('refresh_token');
  if (!rt) return false;
  try {
    const r = await fetch(`${API}/auth/refresh`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: rt })
    });
    if (!r.ok) return false;
    const d = await r.json();
    accessToken = d.access_token;
    localStorage.setItem('access_token', accessToken);
    if (d.refresh_token) localStorage.setItem('refresh_token', d.refresh_token);
    return true;
  } catch { return false; }
}

// =========== INIT ===========
async function initApp() {
  const now = new Date();
  document.getElementById('topbarDate').textContent = now.toLocaleDateString('ru-RU', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
  document.getElementById('dashDate').textContent = new Date().toLocaleDateString('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' });
  try {
    const me = await apiFetch('/auth/me');
    if (me) {
      document.getElementById('sidebarName').textContent = me.username;
      document.getElementById('sidebarAvatar').textContent = me.username[0].toUpperCase();
    }
  } catch (_) { }
  loadDashboard();
  loadRequestsBadge();
  loadPendingBadge();
}

// =========== NAVIGATION ===========
function showPage(name, el) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.sidebar-item').forEach(i => i.classList.remove('active'));
  document.getElementById('page-' + name).classList.add('active');
  el.classList.add('active');
  const titles = {
    dashboard: 'Дашборд',
    employees: 'Сотрудники',
    attendance: 'Посещаемость',
    duty: 'Дежурство',
    news: 'Новости',
    schedule: 'Расписание',
    networks: 'Офисные сети',
    qr: 'QR-коды',
    reports: 'Отчёты',
    worktime: 'Рабочее время',
    requests: 'Заявки',
    auditlog: 'Журнал действий',
  };
  document.getElementById('pageTitle').textContent = titles[name] || name;

  if (name === 'employees') loadEmployees();
  else if (name === 'attendance') { setDefaultDates(); loadAttendance(); }
  else if (name === 'networks') loadNetworks();
  else if (name === 'qr') { loadCurrentQR(); loadQrHistory(); }
  else if (name === 'reports') initReportsPage();
  else if (name === 'worktime') loadWorkTimeSettings();
  else if (name === 'requests') loadRequests();
  else if (name === 'duty') loadDutySchedule();
  else if (name === 'news') loadNews();
  else if (name === 'schedule') loadScheduleEmployeeList();
  else if (name === 'auditlog') loadAuditLog();

  const sidebar = document.querySelector('.sidebar.open');
  if (sidebar) toggleSidebar();
}

function toggleSidebar() {
  const sidebar = document.querySelector('.sidebar');
  const backdrop = document.getElementById('sidebarBackdrop');
  if (!sidebar || !backdrop) return;
  sidebar.classList.toggle('open');
  backdrop.classList.toggle('open');
}

// =========== DASHBOARD ===========
async function loadDashboard() {
  try {
    const today = new Date().toISOString().split('T')[0];
    const report = await apiFetch(`/reports/daily?report_date=${today}`);
    const s = report.summary;

    const total = Math.max(Number(s.total_employees || 0), 0);
    const workedToday = Math.max(Number(s.worked_today || 0), 0);
    const inOfficeNow = Math.max(Number(s.in_office_now || 0), 0);
    const late = Math.max(Number(s.late || 0), 0);
    const absent = Math.max(Number(s.absent || 0), 0);
    const approvedAbsence = Math.max(Number(s.approved_absence || 0), 0);
    const completed = Math.max(Number(s.completed || 0), 0);
    const incomplete = Math.max(Number(s.incomplete || 0), 0);
    const attendanceRate = total > 0 ? Math.min(Math.round((workedToday / total) * 100), 100) : 0;

    document.getElementById('statTotal').textContent = total;
    document.getElementById('statPresent').textContent = inOfficeNow;
    document.getElementById('statLate').textContent = late;
    document.getElementById('statAbsent').textContent = absent;
    document.getElementById('attendanceRate').textContent = attendanceRate + '%';

    const bars = document.getElementById('progressBars');
    const barItems = [
      { l: 'Были сегодня', v: workedToday, c: 'var(--primary)' },
      { l: 'Сейчас в офисе', v: inOfficeNow, c: 'var(--accent)' },
      { l: 'Опоздали', v: late, c: 'var(--warning)' },
      { l: 'Не пришли', v: absent, c: 'var(--error)' },
      { l: 'Разреш. отсутствие', v: approvedAbsence, c: '#5C6BC0' },
      { l: 'Завершили день', v: completed, c: '#1A73E8' },
      { l: 'Не завершили', v: incomplete, c: '#7B61FF' },
    ];
    bars.innerHTML = barItems.map(({ l, v, c }) => `
      <div class="progress-bar-wrap">
        <span class="progress-label">${l}</span>
        <div class="progress-bar">
          <div class="progress-fill" style="width:${total > 0 ? Math.round((v / total) * 100) : 0}%;background:${c}"></div>
        </div>
        <span class="progress-val" style="color:${c}">${v}</span>
      </div>
    `).join('');

    const latest = document.getElementById('latestRecords');
    const detail = (report.detail || []).slice(0, 5);

    if (!detail.length) {
      latest.innerHTML = '<p style="color:var(--text-muted); text-align:center; padding:20px">Нет данных за сегодня</p>';
      return;
    }

    latest.innerHTML = detail.map(r => `
      <div style="display:flex; align-items:center; justify-content:space-between; padding:10px 0; border-bottom:1px solid var(--border)">
        <div>
          <div style="font-weight:700; font-size:14px">${r.employee_name || r.full_name || '—'}</div>
          <div style="font-size:12px; color:var(--text-sub)">
            ${r.team_name || '—'} • ${r.check_in_time ? r.check_in_time + ' →' : '—'} ${r.check_out_time || ''}
          </div>
        </div>
        ${statusBadge(r.status)}
      </div>
    `).join('');

    // Недельный график
    try {
      const weekEnd = today;
      const weekStartD = new Date(Date.now() - 6 * 86400000);
      const weekStart = weekStartD.toISOString().split('T')[0];
      const weekly = await apiFetch(`/reports/period?start_date=${weekStart}&end_date=${weekEnd}`);
      renderDashWeekChart(weekly.chart_data || []);
    } catch (err) {
      console.error('Ошибка загрузки недельного графика:', err);
      const wrap = document.getElementById('dashWeekChartWrap');
      if (wrap) wrap.innerHTML = `<p style="color:var(--text-muted);text-align:center;padding:80px 0">Ошибка загрузки данных</p>`;
    }

  } catch (e) {
    console.error(e);
    showToast('Ошибка загрузки дашборда: ' + e.message, 'error');
  }
}

let dashWeekChart = null;
function renderDashWeekChart(chartData) {
  if (dashWeekChart) { dashWeekChart.destroy(); dashWeekChart = null; }
  const wrap = document.getElementById('dashWeekChartWrap');
  const canvas = document.getElementById('dashWeekChart');
  if (!canvas) return;

  if (!chartData || !chartData.length) {
    if (wrap) wrap.innerHTML = '<p style="color:var(--text-muted);text-align:center;padding:80px 0">Нет данных за неделю</p>';
    return;
  }

  const dayLabels = ['Вс', 'Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб'];
  const labels = chartData.map(d => {
    const dt = new Date(d.date + 'T00:00:00');
    return dayLabels[dt.getDay()] + ' ' + dt.getDate();
  });

  dashWeekChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels,
      datasets: [
        { label: 'Присутствовали', data: chartData.map(d => d.present), backgroundColor: 'rgba(24,119,242,0.75)', borderRadius: 6 },
        { label: 'Опоздали', data: chartData.map(d => d.late), backgroundColor: 'rgba(251,188,4,0.75)', borderRadius: 6 },
        { label: 'Отсутствовали', data: chartData.map(d => d.absent), backgroundColor: 'rgba(234,67,53,0.6)', borderRadius: 6 },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { position: 'bottom' } },
      scales: { x: { stacked: false }, y: { beginAtZero: true, ticks: { stepSize: 1 } } },
    },
  });
}
// =========== EMPLOYEES ===========
async function loadEmployees() {
  try {
    const showInactive = document.getElementById('showInactiveEmployees')?.checked;
    allEmployees = await fetchAllUsers();
    let list = allEmployees.filter(e => e.status !== 'PENDING');
    if (!showInactive) list = list.filter(e => e.status === 'ACTIVE');
    renderEmployees(list);
  } catch (e) {
    document.getElementById('employeesTable').innerHTML =
      `<tr><td colspan="6" style="text-align:center; color:var(--error); padding:32px">Ошибка: ${e.message}</td></tr>`;
  }
}
function renderEmployees(list) {
  const tbody = document.getElementById('employeesTable');

  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; color:var(--text-muted); padding:32px">Нет сотрудников</td></tr>';
    return;
  }

  // Сортировка по алфавиту
  list.sort((a, b) => (a.full_name || '').localeCompare(b.full_name || ''));

  const roleLabels = { SUPER_ADMIN: 'Супер Админ', ADMIN: 'Админ', TEAM_LEAD: 'Тимлид', EMPLOYEE: 'Сотрудник', INTERN: 'Стажёр' };
  const statusLabels = { ACTIVE: 'Активен', BLOCKED: 'Заблокирован', LEAVE: 'В отпуске', WARNING: 'Предупреждение', DELETED: 'Удалён' };
  const mediaBase = API.replace(/\/api\/v1\/?$/, '');
  tbody.innerHTML = list.map(e => {
    const avatarUrl = e.avatar_url ? (e.avatar_url.startsWith('http') ? e.avatar_url : `${mediaBase}${e.avatar_url}`) : null;
    const avatarHtml = avatarUrl
      ? `<img src="${avatarUrl}" style="width:36px;height:36px;border-radius:10px;object-fit:cover;" onerror="this.style.display='none';this.nextElementSibling.style.display='flex'">`
      : '';
    const initialHtml = `<div style="width:36px;height:36px;background:rgba(26,115,232,0.1);border-radius:10px;display:${avatarUrl ? 'none' : 'flex'};align-items:center;justify-content:center;font-weight:800;color:var(--primary)">${(e.full_name || '?')[0].toUpperCase()}</div>`;
    return `
    <tr>
      <td>
        <div style="display:flex; align-items:center; gap:12px">
          <div style="position:relative;width:36px;height:36px;flex-shrink:0">
            ${avatarHtml}${initialHtml}
          </div>
          <div>
            <div style="font-weight:700">${e.full_name || '—'}</div>
            <div style="font-size:12px; color:var(--text-sub)">@${e.username || '—'}</div>
          </div>
        </div>
      </td>
      <td>${e.team_name || '—'}</td>
      <td>${roleLabels[e.role] || e.role || '—'}</td>
      <td style="color:var(--text-sub)">${e.email || '—'}</td>
      <td>
        ${e.status === 'ACTIVE'
        ? '<span class="badge badge-active">Активен</span>'
        : `<span class="badge badge-inactive">${statusLabels[e.status] || e.status}</span>`}
      </td>
      <td style="display:flex; gap:8px; flex-wrap:wrap">
        <button class="btn btn-ghost btn-sm" onclick="openEmployeeProfile('${e.id}')" style="color:var(--primary); border-color:var(--primary)">👤 Профиль</button>
        ${e.status === 'ACTIVE'
        ? `<button class="btn btn-ghost btn-sm" onclick="deactivateEmployee('${e.id}')" style="color:var(--warning); border-color:var(--warning)">Деакт.</button>`
        : (e.status !== 'DELETED' ? `<button class="btn btn-ghost btn-sm" onclick="activateEmployee('${e.id}')" style="color:var(--accent); border-color:var(--accent)">Актив.</button>` : '')}
        ${e.status !== 'DELETED' ? `<button class="btn btn-ghost btn-sm" onclick="openResetPassword('${e.id}', '${(e.full_name || '').replace(/'/g, '&apos;')}')" style="color:var(--primary); border-color:var(--primary)">🔑 Пароль</button>` : ''}
        <button class="btn btn-danger btn-sm" onclick="deleteEmployee('${e.id}')">Удалить</button>
      </td>
    </tr>
  `;
  }).join('');
}


// ── Employee Profile Modal ────────────────────────────────────────────────────
async function openEmployeeProfile(userId) {
  const mediaBase = API.replace(/\/api\/v1\/?$/, '');
  var emp = null;
  try {
    emp = await apiFetch(`/users/${userId}`);
  } catch (e) {
    showToast('Ошибка загрузки профиля: ' + e.message, 'error');
    return;
  }

  const avatarSrc = emp.avatar_url
    ? (emp.avatar_url.startsWith('http') ? emp.avatar_url : `${mediaBase}${emp.avatar_url}`)
    : null;

  const roleLabels = { SUPER_ADMIN: 'Супер Админ', ADMIN: 'Админ', TEAM_LEAD: 'Тимлид', EMPLOYEE: 'Сотрудник', INTERN: 'Стажёр' };
  const statusLabels = { ACTIVE: 'Активен', PENDING: 'Ожидает', BLOCKED: 'Заблокирован', LEAVE: 'В отпуске', WARNING: 'Предупреждение', DELETED: 'Удалён' };

  const avatarBlock = avatarSrc
    ? `<img id="empProfilePhoto" src="${avatarSrc}" style="width:100px;height:100px;border-radius:50%;object-fit:cover;border:3px solid var(--primary)" onerror="this.src='';this.style.display='none';document.getElementById('empProfileInitial').style.display='flex'">`
    : '';
  const initialBlock = `<div id="empProfileInitial" style="width:100px;height:100px;border-radius:50%;background:rgba(26,115,232,0.1);display:${avatarSrc ? 'none' : 'flex'};align-items:center;justify-content:center;font-size:40px;font-weight:800;color:var(--primary)">${(emp.full_name || '?')[0].toUpperCase()}</div>`;

  const fields = [
    ['ФИО', emp.full_name],
    ['Логин', '@' + (emp.username || '—')],
    ['Email', emp.email || '—'],
    ['Телефон', emp.phone || '—'],
    ['Роль', roleLabels[emp.role] || emp.role || '—'],
    ['Статус', statusLabels[emp.status] || emp.status || '—'],
    ['Команда', emp.team_name || '—'],
    ['Дата найма', emp.hired_at || '—'],
    ['Комментарий', emp.admin_comment || '—'],
  ];

  const modal = document.createElement('div');
  modal.className = 'modal-overlay open';
  modal.id = 'empProfileModal';
  modal.innerHTML = `
    <div class="modal" style="max-width:480px;width:100%">
      <div class="modal-header">
        <span class="modal-title">Профиль сотрудника</span>
        <button class="modal-close" onclick="document.getElementById('empProfileModal').remove()">✕</button>
      </div>
      <div style="padding:20px">
        <div style="display:flex;flex-direction:column;align-items:center;gap:12px;margin-bottom:20px">
          <div style="position:relative">
            ${avatarBlock}${initialBlock}
            <label title="Загрузить фото" style="position:absolute;bottom:0;right:0;background:var(--primary);color:#fff;border-radius:50%;width:28px;height:28px;display:flex;align-items:center;justify-content:center;cursor:pointer;font-size:14px">
              📷<input type="file" accept="image/jpeg,image/png" style="display:none" onchange="uploadEmployeeAvatar('${emp.id}', this)">
            </label>
          </div>
          <div id="empProfileNameDisplay" style="font-size:18px;font-weight:800;color:var(--text)">${emp.full_name || '—'}</div>
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
          ${fields.map(([label, value]) => `
            <div style="background:var(--bg);border-radius:10px;padding:10px">
              <div style="font-size:11px;color:var(--text-sub);margin-bottom:3px">${label}</div>
              <div style="font-size:13px;font-weight:600;color:var(--text);word-break:break-word">${value || '—'}</div>
            </div>
          `).join('')}
        </div>

        <div style="margin-top:16px;border-top:1px solid var(--border);padding-top:16px">
          <div style="font-size:14px;font-weight:700;margin-bottom:12px;color:var(--text)">✏️ Редактирование</div>
          
          <div class="form-group">
            <label class="form-label" style="font-size:12px">ФИО *</label>
            <input id="empEditFullName" class="form-input" value="${escHtml(emp.full_name || '')}">
          </div>
          
          <div class="form-group">
            <label class="form-label" style="font-size:12px">Логин *</label>
            <input id="empEditUsername" class="form-input" value="${escHtml(emp.username || '')}">
          </div>

          <div class="form-group">
            <label class="form-label" style="font-size:12px">Телефон</label>
            <input id="empEditPhone" class="form-input" value="${escHtml(emp.phone || '')}" placeholder="+996...">
          </div>

          <div class="form-group">
            <label class="form-label" style="font-size:12px">Команда/отдел</label>
            <input id="empEditTeam" class="form-input" value="${escHtml(emp.team_name || '')}">
          </div>

          <div class="form-group">
            <label class="form-label" style="font-size:12px">Роль</label>
            <select id="empEditRole" class="form-input" data-original="${emp.role}">
              <option value="EMPLOYEE" ${emp.role === 'EMPLOYEE' ? 'selected' : ''}>Сотрудник</option>
              <option value="INTERN" ${emp.role === 'INTERN' ? 'selected' : ''}>Стажёр</option>
              <option value="TEAM_LEAD" ${emp.role === 'TEAM_LEAD' ? 'selected' : ''}>Тимлид</option>
              <option value="ADMIN" ${emp.role === 'ADMIN' ? 'selected' : ''}>Админ</option>
              <option value="SUPER_ADMIN" ${emp.role === 'SUPER_ADMIN' ? 'selected' : ''}>Супер Админ</option>
            </select>
          </div>
          <input type="hidden" id="empOriginalRole" value="${emp.role}">

          <div style="display:flex;gap:8px;margin-top:10px">
            <button class="btn btn-primary" onclick="saveEmployeeDetails('${emp.id}')" style="width:100%">Сохранить изменения</button>
          </div>
        </div>
      </div>
    </div>
  `;
  modal.addEventListener('click', (e) => { if (e.target === modal) modal.remove(); });
  document.body.appendChild(modal);
}

async function saveEmployeeDetails(userId) {
  const fullName = document.getElementById('empEditFullName').value.trim();
  const username = document.getElementById('empEditUsername').value.trim();
  const phone = document.getElementById('empEditPhone').value.trim();
  const team_name = document.getElementById('empEditTeam').value.trim();
  const role = document.getElementById('empEditRole').value;
  const originalRole = document.getElementById('empOriginalRole').value;

  // Валидация
  if (!fullName) return showToast('Введите ФИО', 'error');
  if (username.length < 3) return showToast('Логин должен быть не менее 3 символов', 'error');
  if (!/^[a-zA-Z0-9._]+$/.test(username)) return showToast('Логин может содержать только латиницу, цифры, точки и подчеркивания', 'error');
  if (phone && !/^\+?[0-9]{9,15}$/.test(phone)) return showToast('Неверный формат телефона', 'error');

  try {
    const payload = {
      full_name: fullName,
      username: username,
      phone: phone || null,
      team_name: team_name || null
    };

    // Если роль изменилась — вызываем отдельный endpoint
    if (role !== originalRole) {
      await apiFetch(`/users/${userId}/role`, {
        method: 'PATCH',
        body: JSON.stringify({ role: role }),
      });
    }

    const updated = await apiFetch(`/users/${userId}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });

    // Обновляем в локальном кэше
    const idx = allEmployees.findIndex(e => e.id === userId);
    if (idx !== -1) allEmployees[idx] = { ...allEmployees[idx], ...updated };

    filterEmployees();
    showToast('Данные обновлены', 'success');
    document.getElementById('empProfileModal').remove();
  } catch (e) {
    showToast('Ошибка: ' + e.message, 'error');
  }
}

async function uploadEmployeeAvatar(userId, input) {
  const file = input.files[0];
  if (!file) return;
  const formData = new FormData();
  formData.append('file', file);
  try {
    const r = await fetch(`${API}/users/${userId}/avatar`, {
      method: 'PATCH',
      headers: { 'Authorization': `Bearer ${accessToken}` },
      body: formData,
    });
    if (!r.ok) { const d = await r.json(); throw new Error(d.detail || 'Ошибка загрузки'); }
    const data = await r.json();
    const mediaBase = API.replace(/\/api\/v1\/?$/, '');
    const src = data.avatar_url.startsWith('http') ? data.avatar_url : `${mediaBase}${data.avatar_url}`;
    const img = document.getElementById('empProfilePhoto');
    const ini = document.getElementById('empProfileInitial');
    if (img) { img.src = src; img.style.display = ''; }
    else {
      const newImg = document.createElement('img');
      newImg.id = 'empProfilePhoto';
      newImg.src = src;
      newImg.style = 'width:100px;height:100px;border-radius:50%;object-fit:cover;border:3px solid var(--primary)';
      ini?.parentElement?.insertBefore(newImg, ini);
    }
    if (ini) ini.style.display = 'none';
    // update cached employee avatar
    const emp = allEmployees.find(e => e.id === userId);
    if (emp) emp.avatar_url = data.avatar_url;
    showToast('Фото обновлено', 'success');
  } catch (e) {
    showToast('Ошибка: ' + e.message, 'error');
  }
}

function filterEmployees() {
  const searchEl = document.getElementById('globalSearch');
  const search = searchEl ? searchEl.value.toLowerCase() : '';
  const dept = document.getElementById('empDeptFilter').value.toLowerCase();
  const role = document.getElementById('empRoleFilter').value;
  const showInactive = document.getElementById('showInactiveEmployees')?.checked;
  let base = allEmployees.filter(e => e.status !== 'PENDING');
  if (!showInactive) base = base.filter(e => e.status === 'ACTIVE');

  renderEmployees(
    base.filter(e =>
      (!search || (e.full_name || '').toLowerCase().includes(search) || (e.username || '').toLowerCase().includes(search)) &&
      (!dept || (e.team_name || '').toLowerCase().includes(dept)) &&
      (!role || e.role === role)
    )
  );
}

let currentEmpTab = 'active';

function switchEmpTab(tab, el) {
  currentEmpTab = tab;
  document.querySelectorAll('#page-employees .tab-btn').forEach(b => b.classList.remove('active'));
  el.classList.add('active');
  document.getElementById('empActiveSection').style.display = tab === 'active' ? '' : 'none';
  document.getElementById('empPendingSection').style.display = tab === 'pending' ? '' : 'none';
  if (tab === 'pending') loadPendingEmployees();
}

async function loadPendingEmployees() {
  try {
    let pending = [];
    let page = 1;
    const limit = 100;
    while (true) {
      const data = await apiFetch(`/users/pending?page=${page}&limit=${limit}`);
      if (!data?.items?.length) break;
      pending.push(...data.items);
      if (data.items.length < limit || pending.length >= (data.total ?? 0)) break;
      page++;
    }
    const tbody = document.getElementById('pendingTable');
    if (!pending.length) {
      tbody.innerHTML = '<tr><td colspan="5" style="text-align:center; color:var(--text-muted); padding:32px">Нет ожидающих подтверждения</td></tr>';
      return;
    }
    tbody.innerHTML = pending.map(e => `
      <tr>
        <td>
          <div style="font-weight:700">${e.full_name}</div>
          <div style="font-size:12px; color:var(--text-sub)">@${e.username}</div>
        </td>
        <td style="color:var(--text-sub)">${e.email}</td>
        <td style="color:var(--text-sub)">${e.phone || '—'}</td>
        <td style="color:var(--text-sub)">${e.created_at ? new Date(e.created_at).toLocaleString('ru-RU') : '—'}</td>
        <td style="display:flex; gap:6px; flex-wrap:wrap">
          <button class="btn btn-ghost btn-sm" onclick="approveEmployee('${e.id}')" style="color:var(--accent); border-color:var(--accent)">✓ Одобрить</button>
          <button class="btn btn-danger btn-sm" onclick="rejectEmployee('${e.id}')">✕ Отклонить</button>
        </td>
      </tr>
    `).join('');
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function approveEmployee(id) {
  try {
    await apiFetch(`/users/${id}/approve`, { method: 'PATCH', body: JSON.stringify({ role: 'EMPLOYEE' }) });
    showToast('Сотрудник одобрен', 'success');
    loadPendingEmployees();
    loadPendingBadge();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function rejectEmployee(id) {
  const reason = prompt('Причина отклонения (необязательно):') || '';
  try {
    await apiFetch(`/users/${id}/reject`, { method: 'PATCH', body: JSON.stringify({ reason }) });
    showToast('Заявка отклонена', 'success');
    loadPendingEmployees();
    loadPendingBadge();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function loadPendingBadge() {
  try {
    const data = await apiFetch('/users/pending?limit=1&page=1');
    const count = data.total ?? 0;
    const badge = document.getElementById('pendingBadge');
    const tabCount = document.getElementById('pendingTabCount');
    if (count > 0) {
      badge.style.display = 'inline-block'; badge.textContent = count;
      tabCount.style.display = 'inline-block'; tabCount.textContent = count;
    } else {
      badge.style.display = 'none';
      tabCount.style.display = 'none';
    }
  } catch (_) { }
}

async function createEmployee() {
  const fullName = document.getElementById('empFullName').value.trim();
  const email = document.getElementById('empEmail').value.trim();
  const username = document.getElementById('empUsername').value.trim();
  const password = document.getElementById('empPassword').value;
  const phone = document.getElementById('empPhone').value.trim();

  // Валидация
  if (!fullName) return showToast('Введите ФИО', 'error');
  if (!email || !email.includes('@')) return showToast('Введите корректный Email', 'error');
  if (username.length < 3) return showToast('Логин должен быть не менее 3 символов', 'error');
  if (!/^[a-zA-Z0-9._]+$/.test(username)) return showToast('Логин может содержать только латиницу, цифры, точки и подчеркивания', 'error');
  if (password.length < 6) return showToast('Пароль должен быть не менее 6 символов', 'error');
  if (phone && !/^\+?[0-9]{9,15}$/.test(phone)) return showToast('Неверный формат телефона', 'error');

  try {
    await apiFetch('/users', {
      method: 'POST', body: JSON.stringify({
        full_name: fullName,
        email: email,
        phone: phone || null,
        team_name: document.getElementById('empDept').value || null,
        username: username,
        password: password,
      })
    });
    closeModal('addEmployee');
    showToast('Сотрудник создан', 'success');
    loadEmployees();
  } catch (e) { showToast(e.message, 'error'); }
}

async function activateEmployee(id) {
  try {
    await apiFetch(`/users/${id}/activate`, { method: 'PATCH' });
    showToast('Сотрудник активирован', 'success');
    loadEmployees();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function deleteEmployee(id) {
  if (!confirm('Полностью удалить сотрудника? Если у него есть история, backend не даст удалить.')) return;
  try {
    await apiFetch(`/users/${id}`, { method: 'DELETE' });
    showToast('Сотрудник удалён', 'success');
    loadEmployees();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function deactivateEmployee(id) {
  if (!confirm('Деактивировать сотрудника?')) return;
  try {
    await apiFetch(`/users/${id}/deactivate`, { method: 'PATCH' });
    showToast('Сотрудник деактивирован', 'success');
    loadEmployees();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

// =========== RESET PASSWORD ===========
function openResetPassword(id, name) {
  document.getElementById('resetPwdUserId').value = id;
  document.getElementById('resetPwdUserName').textContent = name;
  document.getElementById('resetPwdInput').value = '';
  document.getElementById('resetPwdConfirm').value = '';
  document.getElementById('resetPwdError').textContent = '';
  openModal('resetPassword');
}

async function confirmResetPassword() {
  const id = document.getElementById('resetPwdUserId').value;
  const pwd = document.getElementById('resetPwdInput').value.trim();
  const pwd2 = document.getElementById('resetPwdConfirm').value.trim();
  const errEl = document.getElementById('resetPwdError');

  if (pwd.length < 6) { errEl.textContent = 'Минимум 6 символов'; return; }
  if (pwd !== pwd2) { errEl.textContent = 'Пароли не совпадают'; return; }

  try {
    await apiFetch(`/users/${id}/reset-password`, {
      method: 'PATCH',
      body: JSON.stringify({ new_password: pwd }),
    });
    closeModal('resetPassword');
    showToast('Пароль успешно сброшен — передайте его сотруднику лично', 'success');
  } catch (e) {
    errEl.textContent = e.message || 'Ошибка';
  }
}

// =========== ATTENDANCE ===========
function setDefaultDates() {
  const today = new Date().toISOString().split('T')[0];
  const weekAgo = new Date(Date.now() - 7 * 86400000).toISOString().split('T')[0];
  document.getElementById('attStartDate').value = weekAgo;
  document.getElementById('attEndDate').value = today;
}

async function loadAttendance() {
  const s = document.getElementById('attStartDate').value;
  const e = document.getElementById('attEndDate').value;
  const id = document.getElementById('attEmpId').value;
  let url = '/attendance?';
  if (s) url += `start_date=${s}&`;
  if (e) url += `end_date=${e}&`;
  if (id) url += `user_id=${encodeURIComponent(id)}&`;
  try {
    const records = await apiFetch(url) || [];
    renderAttendance(records);
  } catch (err) {
    document.getElementById('attendanceTable').innerHTML = `<tr><td colspan="10" style="text-align:center; color:var(--error); padding:32px">Ошибка: ${err.message}</td></tr>`;
  }
}

function renderAttendance(list) {
  const tbody = document.getElementById('attendanceTable');

  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="11" style="text-align:center; color:var(--text-muted); padding:32px">Нет записей</td></tr>';
    return;
  }

  tbody.innerHTML = list.map(r => `
    <tr>
      <td style="font-weight:700">${r.date || '—'}</td>
      <td>
        <div style="font-weight:700">${r.employee_name || '—'}</div>
      </td>
      <td style="color:var(--accent); font-weight:700">${r.formatted_check_in || '—'}</td>
      <td style="color:var(--error); font-weight:700">${r.formatted_check_out || '—'}</td>
      <td>${r.work_duration || '—'}</td>
      <td>${statusBadge(r.status)}</td>
      <td>${r.late_minutes > 0 ? `<span style="color:var(--warning); font-weight:700">${r.late_minutes} мин</span>` : '—'}</td>
      <td>${r.early_arrival_minutes > 0 ? `<span style="color:var(--accent); font-weight:700">${r.early_arrival_minutes} мин</span>` : '—'}</td>
      <td>${r.early_leave_minutes > 0 ? `<span style="color:var(--error); font-weight:700">${r.early_leave_minutes} мин</span>` : '—'}</td>
      <td>${r.overtime_minutes > 0 ? `<span style="color:var(--primary); font-weight:700">${r.overtime_minutes} мин</span>` : '—'}</td>
      <td style="display:flex; gap:6px; flex-wrap:wrap">
        ${!r.check_out_time
      ? `<button class="btn btn-ghost btn-sm" onclick="openManualCheckout('${r.id}', '${(r.employee_name || '').replace(/'/g, '')}')" style="color:var(--primary); border-color:var(--primary)">⏱ Уход</button>`
      : '—'}
      </td>
    </tr>
  `).join('');
}

function resetAttFilters() {
  setDefaultDates();
  document.getElementById('attEmpId').value = '';
  loadAttendance();
}

// =========== REQUESTS ===========
const requestTypeLabelMap = {
  sick: 'Больничный',
  family: 'Семейные обстоятельства',
  vacation: 'Отпуск',
  business_trip: 'Командировка',
  remote_work: 'Удалённая работа',
  late_reason: 'Опоздание (по причине)',
  early_leave: 'Ранний уход (по причине)',
  other: 'Другое'
};

const requestStatusLabelMap = {
  new: 'Новая',
  reviewing: 'Рассматривается',
  approved: 'Одобрена',
  rejected: 'Отклонена',
  needs_clarification: 'Нужно уточнение'
};

async function loadRequests() {
  const status = document.getElementById('reqStatus')?.value || '';
  const employeeId = document.getElementById('reqEmpId')?.value || '';
  const requestType = document.getElementById('reqType')?.value || '';
  let url = '/absence-requests?';
  if (status) url += `status=${encodeURIComponent(status)}&`;
  if (employeeId) url += `user_id=${encodeURIComponent(employeeId)}&`;
  if (requestType) url += `request_type=${encodeURIComponent(requestType)}&`;

  try {
    const rows = await apiFetch(url) || [];
    renderRequests(rows);
    await loadRequestsBadge();
  } catch (e) {
    document.getElementById('requestsTable').innerHTML =
      `<tr><td colspan="8" style="text-align:center; color:var(--error); padding:32px">Ошибка: ${e.message}</td></tr>`;
  }
}

function renderRequests(list) {
  const tbody = document.getElementById('requestsTable');
  if (!list.length) {
    tbody.innerHTML = '<tr><td colspan="8" style="text-align:center; color:var(--text-muted); padding:32px">Нет заявок</td></tr>';
    return;
  }

  tbody.innerHTML = list.map(r => {
    const period = r.end_date ? `${r.start_date} — ${r.end_date}` : r.start_date;
    const typeLabel = requestTypeLabelMap[r.request_type] || r.request_type;
    const statusLabel = requestStatusLabelMap[r.status] || r.status;
    const isResolved = ['approved', 'rejected', 'needs_clarification'].includes(r.status);
    return `
      <tr>
        <td>
          <div style="font-weight:700">${r.user_full_name || '—'}</div>
        </td>
        <td>${typeLabel}</td>
        <td>${period}${r.start_time ? `<div style="font-size:12px;color:var(--text-sub)">в ${String(r.start_time).slice(0, 5)}</div>` : ''}</td>
        <td style="max-width:260px; white-space:normal">${r.comment_employee || '—'}</td>
        <td>${statusBadgeForRequest(r.status, statusLabel)}</td>
        <td style="max-width:220px; white-space:normal">${r.comment_admin || '—'}</td>
        <td style="display:flex; gap:6px; flex-wrap:wrap">
          ${isResolved ? '<span style="font-size:12px; color:var(--text-sub)">Завершено</span>' : `
            <button class="btn btn-ghost btn-sm" style="color:var(--accent); border-color:var(--accent)" onclick="reviewRequest('${r.id}', 'approved')">Одобрить</button>
            <button class="btn btn-ghost btn-sm" style="color:var(--error); border-color:var(--error)" onclick="reviewRequest('${r.id}', 'rejected')">Отклонить</button>
            <button class="btn btn-ghost btn-sm" style="color:var(--warning); border-color:var(--warning)" onclick="reviewRequest('${r.id}', 'needs_clarification')">Уточнить</button>
          `}
        </td>
      </tr>
    `;
  }).join('');
}

function statusBadgeForRequest(status, label) {
  const map = {
    new: 'badge-completed',
    reviewing: 'badge-late',
    approved: 'badge-present',
    rejected: 'badge-absent',
    needs_clarification: 'badge-approved-absence'
  };
  const cls = map[status] || 'badge-manual';
  return `<span class="badge ${cls}">${label}</span>`;
}

async function reviewRequest(requestId, status) {
  let comment = prompt('Комментарий администратора (необязательно):') || '';
  if (status === 'needs_clarification' && !comment.trim()) {
    showToast('Для статуса "нужно уточнение" добавьте комментарий', 'error');
    return;
  }
  try {
    await apiFetch(`/absence-requests/${requestId}/review`, {
      method: 'PATCH',
      body: JSON.stringify({
        status,
        comment_admin: comment.trim() || null
      })
    });
    showToast('Заявка обновлена', 'success');
    await loadRequests();
    loadDashboard();
    if (typeof loadAttendance === 'function') loadAttendance();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

function resetRequestFilters() {
  document.getElementById('reqStatus').value = '';
  document.getElementById('reqEmpId').value = '';
  document.getElementById('reqType').value = '';
  loadRequests();
}

async function loadRequestsBadge() {
  try {
    const requests = await apiFetch('/absence-requests?status=new');
    const count = Array.isArray(requests) ? requests.length : 0;
    const badge = document.getElementById('requestsBadge');
    if (!badge) return;
    if (count > 0) {
      badge.style.display = 'inline-block';
      badge.textContent = count;
    } else {
      badge.style.display = 'none';
    }
  } catch (_) {
    // Ignore badge errors
  }
}



// =========== NETWORKS ===========
async function loadNetworks() {
  try {
    const nets = await apiFetch('/office-networks') || [];
    const tbody = document.getElementById('networksTable');

    if (!nets.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; color:var(--text-muted); padding:32px">Нет сетей</td></tr>';
      return;
    }

    tbody.innerHTML = nets.map(n => `
      <tr>
        <td style="font-weight:700">${n.name}</td>
        <td style="font-family:monospace">${n.public_ip || '—'}</td>
        <td style="font-family:monospace">${n.ip_range || '—'}</td>
        <td style="color:var(--text-sub)">${n.description || '—'}</td>
        <td>
          ${n.is_active
        ? '<span class="badge badge-active">Активна</span>'
        : '<span class="badge badge-inactive">Неактивна</span>'}
        </td>
        <td style="display:flex; gap:8px; flex-wrap:wrap">
          ${n.is_active
        ? `<button class="btn btn-ghost btn-sm" onclick="deactivateNetwork(${n.id})" style="color:var(--warning); border-color:var(--warning)">Деакт.</button>`
        : `<button class="btn btn-ghost btn-sm" onclick="activateNetwork(${n.id})" style="color:var(--accent); border-color:var(--accent)">Актив.</button>`}
          <button class="btn btn-danger btn-sm" onclick="deleteNetwork(${n.id})">Удалить</button>
        </td>
      </tr>
    `).join('');
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function createNetwork() {
  try {
    await apiFetch('/office-networks', {
      method: 'POST',
      body: JSON.stringify({
        name: document.getElementById('netName').value,
        public_ip: document.getElementById('netIp').value || null,
        ip_range: document.getElementById('netRange').value || null,
        description: document.getElementById('netDesc').value || null
      })
    });

    closeModal('addNetwork');
    showToast('Сеть добавлена', 'success');
    loadNetworks();

    document.getElementById('netName').value = '';
    document.getElementById('netIp').value = '';
    document.getElementById('netRange').value = '';
    document.getElementById('netDesc').value = '';
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function activateNetwork(id) {
  try {
    await apiFetch(`/office-networks/${id}/activate`, { method: 'PATCH' });
    showToast('Сеть активирована', 'success');
    loadNetworks();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function deactivateNetwork(id) {
  try {
    await apiFetch(`/office-networks/${id}/deactivate`, { method: 'PATCH' });
    showToast('Сеть деактивирована', 'success');
    loadNetworks();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function deleteNetwork(id) {
  if (!confirm('Удалить сеть?')) return;
  try {
    await apiFetch(`/office-networks/${id}`, { method: 'DELETE' });
    showToast('Сеть удалена', 'success');
    loadNetworks();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

// =========== QR ===========
async function loadCurrentQR() {
  try {
    const data = await apiFetch('/qr/current');
    document.getElementById('qrContainer').innerHTML = `
      <img src="data:image/png;base64,${data.image_base64}" width="200" height="200" alt="QR Code">
      <p style="margin-top:16px; font-size:13px; color:var(--text-sub)">Тип: ${data.type}</p>
      <p style="font-size:11px; font-family:monospace; margin-top:8px; color:var(--text-muted); word-break:break-all">${data.token}</p>
    `;
  } catch (e) {
    document.getElementById('qrContainer').innerHTML = `<p style="color:var(--error)">${e.message}</p>`;
  }
}

async function generateNewQR() {
  if (!confirm('Сгенерировать новый QR-код? Старый перестанет быть активным.')) return;
  try {
    await apiFetch('/qr/generate', { method: 'POST' });
    await loadCurrentQR();
    await loadQrHistory();
    showToast('Новый QR-код сгенерирован', 'success');
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function loadQrHistory() {
  try {
    const list = await apiFetch('/qr') || [];
    const tbody = document.getElementById('qrHistoryTable');

    if (!list.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; color:var(--text-muted); padding:32px">Нет QR-кодов</td></tr>';
      return;
    }

    tbody.innerHTML = list.map(q => `
      <tr>
        <td>${q.id}</td>
        <td>${q.type || 'attendance'}</td>
        <td>${q.created_at ? new Date(q.created_at).toLocaleString('ru-RU') : '—'}</td>
        <td>${q.expires_at ? new Date(q.expires_at).toLocaleString('ru-RU') : '—'}</td>
        <td>
          ${q.is_active
        ? '<span class="badge badge-active">Активен</span>'
        : '<span class="badge badge-inactive">Неактивен</span>'}
        </td>
        <td style="display:flex; gap:8px; flex-wrap:wrap">
          ${q.is_active
        ? `<button class="btn btn-ghost btn-sm" onclick="deactivateQr(${q.id})" style="color:var(--warning); border-color:var(--warning)">Деакт.</button>`
        : `<button class="btn btn-ghost btn-sm" onclick="activateQr(${q.id})" style="color:var(--accent); border-color:var(--accent)">Актив.</button>`}
          <button class="btn btn-danger btn-sm" onclick="deleteQr(${q.id})">Удалить</button>
        </td>
      </tr>
    `).join('');
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function activateQr(id) {
  try {
    await apiFetch(`/qr/${id}/activate`, { method: 'PATCH' });
    showToast('QR активирован', 'success');
    loadCurrentQR();
    loadQrHistory();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function deactivateQr(id) {
  try {
    await apiFetch(`/qr/${id}/deactivate`, { method: 'PATCH' });
    showToast('QR деактивирован', 'success');
    loadCurrentQR();
    loadQrHistory();
  } catch (e) {
    showToast(e.message, 'error');
  }
}

async function deleteQr(id) {
  if (!confirm('Удалить QR?')) return;
  try {
    await apiFetch(`/qr/${id}`, { method: 'DELETE' });
    showToast('QR удалён', 'success');
    loadCurrentQR();
    loadQrHistory();
  } catch (e) {
    showToast(e.message, 'error');
  }
}


// =========== REPORTS ===========
let reportChart = null;
let reportMode = 'period';

function switchReportMode(mode, el) {
  reportMode = mode;
  document.querySelectorAll('#page-reports .tab-btn').forEach(b => b.classList.remove('active'));
  el.classList.add('active');
  document.getElementById('repEmployeeFilter').style.display = mode === 'employee' ? 'block' : 'none';
  loadReports();
}

function setQuickPeriod(type, el) {
  document.querySelectorAll('.period-quick').forEach(b => b.classList.remove('active'));
  el.classList.add('active');
  const today = new Date();
  const todayStr = today.toISOString().split('T')[0];
  let startStr = todayStr;
  if (type === 'week') {
    const mon = new Date(today);
    mon.setDate(today.getDate() - ((today.getDay() + 6) % 7));
    startStr = mon.toISOString().split('T')[0];
  } else if (type === 'month') {
    startStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-01`;
  }
  document.getElementById('repStartDate').value = startStr;
  document.getElementById('repEndDate').value = todayStr;
  loadReports();
}

function clearQuickPeriod() {
  document.querySelectorAll('.period-quick').forEach(b => b.classList.remove('active'));
}

function _repFmtDate(ds) {
  const d = new Date(ds + 'T00:00:00');
  return d.toLocaleDateString('ru-RU', { day: 'numeric', month: 'short' });
}

function _fmtHours(minutes) {
  if (!minutes) return '—';
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return m > 0 ? `${h}ч ${m}м` : `${h}ч`;
}

function _repStatCards(items) {
  return `<div class="stats-grid" style="margin-bottom:20px">
    ${items.map(([l, v, c]) => `
      <div class="stat-card">
        <div class="stat-value" style="color:${c}">${v}</div>
        <div class="stat-label">${l}</div>
      </div>`).join('')}
  </div>`;
}

async function initReportsPage() {
  // Set default date range (current week) and populate employee dropdown
  setQuickPeriod('week', document.getElementById('pq-week'));
  // Populate employee select
  try {
    if (!allEmployees.length) allEmployees = await fetchAllUsers();
    const sel = document.getElementById('repEmployeeId');
    const activeEmps = allEmployees.filter(e => e.status === 'ACTIVE' &&
      !['ADMIN', 'SUPER_ADMIN'].includes(e.role));
    sel.innerHTML = '<option value="">— Выберите сотрудника —</option>' +
      activeEmps.map(e => `<option value="${e.id}">${e.full_name}</option>`).join('');
  } catch (_) { }
}

async function loadReports() {
  if (reportMode === 'employee') await loadEmployeeReport();
  else await loadPeriodReport();
}

async function loadPeriodReport() {
  const start = document.getElementById('repStartDate').value;
  const end = document.getElementById('repEndDate').value;
  if (!start || !end) return;

  document.getElementById('reportContent').innerHTML =
    `<div style="text-align:center;padding:48px;color:var(--text-muted)">Загрузка…</div>`;

  try {
    const data = await apiFetch(`/reports/period?start_date=${start}&end_date=${end}`);
    const s = data.summary;

    // Also load daily detail for the last day in range (or start if range is 1 day)
    const detailDate = start === end ? start : end;
    let dailyDetail = [];
    try {
      const daily = await apiFetch(`/reports/daily?report_date=${detailDate}`);
      dailyDetail = daily.detail || [];
    } catch (_) { }

    document.getElementById('reportContent').innerHTML = `
      ${_repStatCards([
      ['Всего сотрудников', s.total_employees, 'var(--primary)'],
      ['Присутствовали', s.worked_today ?? s.present, 'var(--accent)'],
      ['Опоздали', s.late, 'var(--warning)'],
      ['Отсутствовали', s.absent, 'var(--error)'],
    ])}

      <div class="card" style="margin-bottom:20px">
        <div class="card-header">
          <div>
            <div class="card-title">📊 Посещаемость по дням</div>
            <div class="card-sub">${_repFmtDate(start)} — ${_repFmtDate(end)}</div>
          </div>
        </div>
        <div style="position:relative;height:280px;padding:4px 0">
          <canvas id="reportChartCanvas"></canvas>
        </div>
      </div>

      <div class="card" style="margin-bottom:20px">
        <div class="card-header"><div class="card-title">👥 Сводка по сотрудникам</div></div>
        <div class="table-wrap">
          <table>
            <thead><tr>
              <th>Сотрудник</th><th>Отдел</th>
              <th>Дней присут.</th><th>Часов работал</th>
              <th>Опоздания (дн)</th><th>Опоздание</th>
              <th>Отсутствия</th><th>Разреш. отсут.</th>
            </tr></thead>
            <tbody>${!data.employees.length
        ? '<tr><td colspan="8" style="text-align:center;color:var(--text-muted);padding:32px">Нет данных</td></tr>'
        : data.employees.map(e => `
                <tr>
                  <td style="font-weight:700">${e.full_name || '—'}</td>
                  <td>${e.team_name || '—'}</td>
                  <td style="color:var(--accent);font-weight:700">${e.days_present}</td>
                  <td style="color:var(--primary);font-weight:700">${_fmtHours(e.total_work_minutes)}</td>
                  <td>${e.days_late > 0 ? `<span style="color:var(--warning)">${e.days_late}</span>` : '—'}</td>
                  <td>${e.total_late_minutes > 0 ? `<span style="color:var(--warning)">${_fmtHours(e.total_late_minutes)}</span>` : '—'}</td>
                  <td>${e.days_absent > 0 ? `<span style="color:var(--error)">${e.days_absent}</span>` : '—'}</td>
                  <td>${e.days_approved_absence > 0 ? `<span style="color:var(--primary)">${e.days_approved_absence}</span>` : '—'}</td>
                </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>

      ${dailyDetail.length ? `
      <div class="card">
        <div class="card-header">
          <div class="card-title">📋 Детали за ${_repFmtDate(detailDate)}</div>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr>
              <th>Сотрудник</th><th>Отдел</th>
              <th>Приход</th><th>Уход</th><th>Часы</th>
              <th>Статус</th><th>Опоздание</th>
            </tr></thead>
            <tbody>${dailyDetail.map(d => `
              <tr>
                <td style="font-weight:700">${d.employee_name || d.full_name || '—'}</td>
                <td>${d.team_name || '—'}</td>
                <td style="color:var(--accent)">${d.check_in_time || '—'}</td>
                <td style="color:var(--error)">${d.check_out_time || '—'}</td>
                <td style="color:var(--primary)">${d.work_duration || '—'}</td>
                <td>${statusBadge(d.status)}</td>
                <td>${d.late_minutes > 0 ? `<span style="color:var(--warning)">${d.late_minutes} мин</span>` : '—'}</td>
              </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>` : ''}
    `;

    renderAttendanceChart(data.chart_data);
  } catch (e) { showToast(e.message, 'error'); }
}

async function loadEmployeeReport() {
  const start = document.getElementById('repStartDate').value;
  const end = document.getElementById('repEndDate').value;
  const userId = document.getElementById('repEmployeeId').value;

  if (!userId) {
    document.getElementById('reportContent').innerHTML =
      `<div class="card" style="text-align:center;padding:48px;color:var(--text-muted)">Выберите сотрудника</div>`;
    return;
  }

  document.getElementById('reportContent').innerHTML =
    `<div style="text-align:center;padding:48px;color:var(--text-muted)">Загрузка…</div>`;

  try {
    let url = `/reports/employee/${userId}`;
    const params = [];
    if (start) params.push(`start_date=${start}`);
    if (end) params.push(`end_date=${end}`);
    if (params.length) url += '?' + params.join('&');

    const data = await apiFetch(url);
    const s = data.stats;

    document.getElementById('reportContent').innerHTML = `
      ${_repStatCards([
      ['Дней присутствовал', s.days_present, 'var(--accent)'],
      ['Дней опоздал', s.days_late, 'var(--warning)'],
      ['Опоздание (мин)', s.total_late_minutes, 'var(--warning)'],
      ['Часов работал', _fmtHours(s.total_work_minutes), 'var(--primary)'],
    ])}

      <div class="card">
        <div class="card-header">
          <div>
            <div class="card-title">${data.full_name}</div>
            <div class="card-sub">${start || ''} — ${end || ''}</div>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr>
              <th>Дата</th><th>Приход</th><th>Уход</th><th>Часы</th>
              <th>Статус</th><th>Опоздание</th><th>Примечание</th>
            </tr></thead>
            <tbody>${!data.records.length
        ? '<tr><td colspan="7" style="text-align:center;color:var(--text-muted);padding:32px">Нет записей за период</td></tr>'
        : data.records.map(r => `
                <tr>
                  <td style="font-weight:700">${_repFmtDate(r.date)}</td>
                  <td style="color:var(--accent)">${r.check_in || '—'}</td>
                  <td style="color:var(--error)">${r.check_out || '—'}</td>
                  <td style="color:var(--primary)">${r.work_duration || '—'}</td>
                  <td>${statusBadge(r.status)}</td>
                  <td>${r.late_minutes > 0 ? `<span style="color:var(--warning)">${r.late_minutes} мин</span>` : '—'}</td>
                  <td style="color:var(--text-sub);font-size:12px;font-weight:400">${r.note || '—'}</td>
                </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>
    `;
  } catch (e) { showToast(e.message, 'error'); }
}

function renderAttendanceChart(chartData) {
  if (reportChart) { reportChart.destroy(); reportChart = null; }
  const canvas = document.getElementById('reportChartCanvas');
  if (!canvas || !chartData?.length) return;

  const labels = chartData.map(d => _repFmtDate(d.date));
  reportChart = new Chart(canvas, {
    type: 'bar',
    data: {
      labels,
      datasets: [
        {
          label: 'Присутствовали',
          data: chartData.map(d => d.present),
          backgroundColor: 'rgba(6,214,160,0.8)',
          borderRadius: 6,
          borderSkipped: false,
        },
        {
          label: 'Отсутствовали',
          data: chartData.map(d => d.absent),
          backgroundColor: 'rgba(239,35,60,0.7)',
          borderRadius: 6,
          borderSkipped: false,
        },
        {
          label: 'Опоздали',
          data: chartData.map(d => d.late),
          backgroundColor: 'rgba(255,183,3,0.85)',
          borderRadius: 6,
          borderSkipped: false,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          position: 'top',
          labels: {
            font: { family: 'Inter', size: 12, weight: '600' },
            usePointStyle: true, pointStyle: 'circle', padding: 16,
          },
        },
        tooltip: {
          callbacks: { label: ctx => ` ${ctx.dataset.label}: ${ctx.parsed.y} чел.` },
        },
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: { font: { family: 'Inter', size: 11 } },
        },
        y: {
          beginAtZero: true,
          ticks: { stepSize: 1, font: { family: 'Inter', size: 11 } },
          grid: { color: 'rgba(0,0,0,0.05)' },
        },
      },
    },
  });
}






// =========== DUTY ===========
let dutyTab = 'schedule';

function switchDutyTab(tab, el) {
  dutyTab = tab;
  document.querySelectorAll('#page-duty .tab-btn').forEach(b => b.classList.remove('active'));
  el.classList.add('active');
  if (tab === 'schedule') loadDutySchedule();
  else if (tab === 'calendar') loadDutyCalendar();
  else if (tab === 'stats') loadDutyStats();
  else if (tab === 'history') loadDutyHistory();
  else loadDutyChecklist();
}

async function loadDutySchedule() {
  try {
    const today = new Date().toISOString().split('T')[0];
    const end = new Date(Date.now() + 30 * 86400000).toISOString().split('T')[0];
    const list = await apiFetch(`/duty/schedule?start_date=${today}&end_date=${end}`) || [];

    const typeLabel = t => t === 'LUNCH' ? '🍽️ Обед' : t === 'CLEANING' ? '🧹 Уборка' : t || '—';
    const typeColor = t => t === 'LUNCH' ? 'var(--primary)' : 'var(--accent)';
    const typeBg = t => t === 'LUNCH' ? 'rgba(26,115,232,0.1)' : 'rgba(0,200,83,0.1)';

    document.getElementById('dutyContent').innerHTML = `
      <div class="card">
        <div class="card-header">
          <div class="card-title">Расписание дежурств (30 дней)</div>
          <button class="btn btn-ghost btn-sm" onclick="loadDutySchedule()">🔄 Обновить</button>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Дата</th><th>Сотрудник</th><th>Тип</th><th>Выполнено</th><th>Подтверждено</th><th>Действия</th></tr></thead>
            <tbody>${!list.length
        ? '<tr><td colspan="6" style="text-align:center; color:var(--text-muted); padding:32px">Нет назначений</td></tr>'
        : list.map(d => `
                <tr>
                  <td style="font-weight:700">${d.date}</td>
                  <td><div style="font-weight:700">${d.user_full_name || '—'}</div></td>
                  <td>
                    <span style="background:${typeBg(d.duty_type)};color:${typeColor(d.duty_type)};padding:3px 10px;border-radius:20px;font-size:12px;font-weight:700">
                      ${typeLabel(d.duty_type)}
                    </span>
                  </td>
                  <td>${d.is_completed
            ? '<span class="badge badge-present">✓ Да</span>'
            : '<span class="badge badge-absent">✗ Нет</span>'}</td>
                  <td>${d.verified
            ? '<span class="badge badge-completed">✓ Да</span>'
            : '<span class="badge badge-manual">— Нет</span>'}</td>
                  <td style="display:flex; gap:6px; flex-wrap:wrap">
                    <button class="btn btn-ghost btn-sm" onclick="openTransferDuty('${d.id}', '${d.date}', '${d.user_id}')" style="color:var(--purple); border-color:var(--purple)">🔄 Перенести</button>
                    ${d.is_completed && !d.verified ? `
                      <button class="btn btn-ghost btn-sm" onclick="verifyDuty('${d.id}', true)" style="color:var(--accent); border-color:var(--accent)">✓ Подтв.</button>
                      <button class="btn btn-ghost btn-sm" onclick="verifyDuty('${d.id}', false)" style="color:var(--error); border-color:var(--error)">✕ Откл.</button>
                    ` : (!d.is_completed ? `<button class="btn btn-ghost btn-sm" onclick="manualCompleteDuty('${d.id}')" style="color:var(--warning); border-color:var(--warning)">✏️ Вручную</button>` : '—')}
                  </td>
                </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>`;
  } catch (e) {
    document.getElementById('dutyContent').innerHTML = `<p style="color:var(--error); padding:20px">${e.message}</p>`;
  }
}

async function loadDutyCalendar() {
  try {
    const today = new Date();
    const year = today.getFullYear();
    const month = today.getMonth();
    const firstDay = new Date(year, month, 1);
    const lastDay = new Date(year, month + 1, 0);
    const startDate = firstDay.toISOString().split('T')[0];
    const endDate = lastDay.toISOString().split('T')[0];

    const list = await apiFetch(`/duty/schedule?start_date=${startDate}&end_date=${endDate}`) || [];
    const dutyByDate = {};
    list.forEach(d => {
      if (!dutyByDate[d.date]) dutyByDate[d.date] = [];
      dutyByDate[d.date].push(d);
    });

    const monthNames = ['Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
    const daysOfWeek = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const startPadding = (firstDay.getDay() + 6) % 7;
    const totalCells = startPadding + lastDay.getDate();

    let calendarHTML = `<div class="card">
      <div class="card-header">
        <div class="card-title">📅 ${monthNames[month]} ${year}</div>
      </div>
      <div style="display:grid; grid-template-columns:repeat(7,1fr); gap:4px; text-align:center; margin-bottom:8px">
        ${daysOfWeek.map(d => `<div style="font-size:11px; font-weight:700; color:var(--text-muted); padding:8px 0">${d}</div>`).join('')}
      </div>
      <div style="display:grid; grid-template-columns:repeat(7,1fr); gap:4px">`;

    for (let i = 0; i < totalCells; i++) {
      const dayNum = i - startPadding + 1;
      if (dayNum < 1) {
        calendarHTML += '<div></div>';
      } else {
        const dateStr = `${year}-${String(month + 1).padStart(2, '0')}-${String(dayNum).padStart(2, '0')}`;
        const duties = dutyByDate[dateStr] || [];
        const isToday = dateStr === today.toISOString().split('T')[0];
        const isWeekend = new Date(dateStr).getDay() === 0 || new Date(dateStr).getDay() === 6;

        calendarHTML += `<div style="min-height:80px; background:${isToday ? 'rgba(67,97,238,0.1)' : isWeekend ? 'rgba(0,0,0,0.02)' : 'var(--surface)'}; border:1px solid ${isToday ? 'var(--primary)' : 'var(--border)'}; border-radius:8px; padding:6px">
          <div style="font-size:12px; font-weight:${isToday ? '800' : '600'}; color:${isToday ? 'var(--primary)' : 'var(--text-sub)'}">${dayNum}</div>
          <div style="margin-top:4px">${duties.map(d => `
            <div style="font-size:10px; padding:2px 4px; border-radius:4px; margin-bottom:2px; background:${d.duty_type === 'LUNCH' ? 'var(--primary-light)' : 'var(--accent-light)'}; color:${d.duty_type === 'LUNCH' ? 'var(--primary)' : 'var(--accent)'}; font-weight:600; white-space:nowrap; overflow:hidden; text-overflow:ellipsis">
              ${d.duty_type === 'LUNCH' ? '🍽️' : '🧹'} ${d.user_full_name?.split(' ')[0] || '—'}
            </div>`).join('')}
          </div>
        </div>`;
      }
    }

    calendarHTML += '</div></div>';
    document.getElementById('dutyContent').innerHTML = calendarHTML;
  } catch (e) {
    document.getElementById('dutyContent').innerHTML = `<p style="color:var(--error); padding:20px">${e.message}</p>`;
  }
}

async function manualCompleteDuty(id) {
  if (!confirm('Отметить дежурство как выполненное вручную?')) return;
  try {
    await apiFetch(`/duty/${id}/complete-manual`, { method: 'PATCH' });
    showToast('Дежурство отмечено вручную', 'success');
    loadDutySchedule();
  } catch (e) { showToast(e.message, 'error'); }
}

async function loadDutyStats() {
  try {
    const stats = await apiFetch('/duty/stats') || [];
    const totalDuties = stats.reduce((sum, s) => sum + s.total, 0);
    const completedDuties = stats.reduce((sum, s) => sum + s.completed, 0);

    document.getElementById('dutyContent').innerHTML = `
      <div class="card">
        <div class="card-header">
          <div class="card-title">📊 Статистика дежурств (за 90 дней)</div>
        </div>
        <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:16px; margin-bottom:20px">
          <div style="background:var(--primary-light); padding:16px; border-radius:12px; text-align:center">
            <div style="font-size:28px; font-weight:800; color:var(--primary)">${stats.length}</div>
            <div style="font-size:12px; color:var(--text-sub)">Сотрудников</div>
          </div>
          <div style="background:var(--accent-light); padding:16px; border-radius:12px; text-align:center">
            <div style="font-size:28px; font-weight:800; color:var(--accent)">${totalDuties}</div>
            <div style="font-size:12px; color:var(--text-sub)">Всего дежурств</div>
          </div>
          <div style="background:rgba(0,200,83,0.1); padding:16px; border-radius:12px; text-align:center">
            <div style="font-size:28px; font-weight:800; color:rgb(0,150,0)">${completedDuties}</div>
            <div style="font-size:12px; color:var(--text-sub)">Выполнено</div>
          </div>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Сотрудник</th><th>Всего</th><th>Выполнено</th><th>Подтверждено</th><th>Пропущено</th></tr></thead>
            <tbody>${!stats.length
              ? '<tr><td colspan="5" style="text-align:center; color:var(--text-muted); padding:32px">Нет данных</td></tr>'
              : stats.map(s => `
                <tr>
                  <td style="font-weight:700">${s.full_name || '—'}</td>
                  <td><span class="badge badge-primary">${s.total}</span></td>
                  <td>${s.completed}</td>
                  <td>${s.verified}</td>
                  <td>${s.missed > 0 ? `<span style="color:var(--error); font-weight:700">${s.missed}</span>` : '0'}</td>
                </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>`;
  } catch (e) {
    document.getElementById('dutyContent').innerHTML = `<p style="color:var(--error); padding:20px">${e.message}</p>`;
  }
}

async function loadDutyHistory() {
  try {
    const endDate = new Date().toISOString().split('T')[0];
    const startDate = new Date(Date.now() - 90 * 86400000).toISOString().split('T')[0];
    const list = await apiFetch(`/duty/schedule?start_date=${startDate}&end_date=${endDate}`) || [];

    const typeLabel = t => t === 'LUNCH' ? '🍽️ Обед' : t === 'CLEANING' ? '🧹 Уборка' : t || '—';
    const typeColor = t => t === 'LUNCH' ? 'var(--primary)' : 'var(--accent)';
    const typeBg = t => t === 'LUNCH' ? 'rgba(26,115,232,0.1)' : 'rgba(0,200,83,0.1)';

    // Sort by date descending
    const sorted = [...list].sort((a, b) => new Date(b.date) - new Date(a.date));

    document.getElementById('dutyContent').innerHTML = `
      <div class="card">
        <div class="card-header">
          <div class="card-title">📜 История дежурств (последние 90 дней)</div>
        </div>
        <div class="table-wrap">
          <table>
            <thead><tr><th>Дата</th><th>Сотрудник</th><th>Тип</th><th>Выполнено</th><th>Подтверждено</th></tr></thead>
            <tbody>${!sorted.length
              ? '<tr><td colspan="5" style="text-align:center; color:var(--text-muted); padding:32px">Нет истории</td></tr>'
              : sorted.map(d => `
                <tr>
                  <td style="font-weight:700">${d.date}</td>
                  <td><div style="font-weight:700">${d.user_full_name || '—'}</div></td>
                  <td>
                    <span style="background:${typeBg(d.duty_type)};color:${typeColor(d.duty_type)};padding:3px 10px;border-radius:20px;font-size:12px;font-weight:700">
                      ${typeLabel(d.duty_type)}
                    </span>
                  </td>
                  <td>${d.is_completed
            ? '<span class="badge badge-present">✓ Да</span>'
            : '<span class="badge badge-absent">✗ Нет</span>'}</td>
                  <td>${d.verified
            ? '<span class="badge badge-completed">✓ Да</span>'
            : '<span class="badge badge-manual">— Нет</span>'}</td>
                </tr>`).join('')}
            </tbody>
          </table>
        </div>
      </div>`;
  } catch (e) {
    document.getElementById('dutyContent').innerHTML = `<p style="color:var(--error); padding:20px">${e.message}</p>`;
  }
}

async function autoAssignDuties() {
  const employees = await fetchAllUsers().then(list => list.filter(e => e.status === 'ACTIVE' || e.status === 'WARNING'));
  if (!employees.length) return showToast('Нет активных сотрудников', 'error');

  const startDate = new Date();
  const endDate = new Date(Date.now() + 30 * 86400000);
  const lunchDays = [];
  for (let d = new Date(startDate); d <= endDate; d.setDate(d.getDate() + 1)) {
    const day = d.getDay();
    if (day !== 0 && day !== 6) lunchDays.push(d.toISOString().split('T')[0]);
  }

  if (!confirm(`Назначить дежурных на обед на ${lunchDays.length} рабочих дней? Сотрудники будут распределены по очереди.`)) return;

  try {
    let idx = 0;
    const results = { success: 0, failed: 0 };
    for (const date of lunchDays) {
      try {
        const user = employees[idx % employees.length];
        await apiFetch('/duty/assign', {
          method: 'POST',
          body: JSON.stringify({ user_id: user.id, date, duty_type: 'LUNCH' })
        });
        results.success++;
      } catch (e) {
        results.failed++;
        console.error(`Failed to assign duty for ${date}:`, e);
      }
      idx++;
    }
    showToast(`Назначено ${results.success} дежурств${results.failed > 0 ? ', ' + results.failed + ' ошибок' : ''}`, results.failed > 0 ? 'warning' : 'success');
    loadDutySchedule();
  } catch (e) {
    showToast('Ошибка: ' + e.message, 'error');
  }
}

async function openTransferDuty(id, date, userId) {
  document.getElementById('transferAssignmentId').value = id;
  document.getElementById('transferCurrentDate').textContent = date;
  document.getElementById('transferNewDate').value = date;

  const employees = await fetchAllUsers().then(list => list.filter(e => e.status === 'ACTIVE' || e.status === 'WARNING'));
  document.getElementById('transferNewEmployee').innerHTML = '<option value="">— Оставить того же —</option>' +
    employees.map(e => `<option value="${e.id}">${e.full_name}</option>`).join('');

  openModal('transferDuty');
}

async function saveTransferDuty() {
  const id = document.getElementById('transferAssignmentId').value;
  const newDate = document.getElementById('transferNewDate').value;
  const newUserId = document.getElementById('transferNewEmployee').value;

  if (!newDate) return showToast('Выберите новую дату', 'error');

  try {
    await apiFetch(`/duty/assign/${id}/move`, {
      method: 'PATCH',
      body: JSON.stringify({
        new_date: newDate,
        new_user_id: newUserId || null
      })
    });
    showToast('Дежурство перенесено', 'success');
    closeModal('transferDuty');
    loadDutySchedule();
  } catch (e) {
    showToast('Ошибка: ' + e.message, 'error');
  }
}

async function loadDutyChecklist() {
  try {
    const [lunch, cleaning] = await Promise.all([
      apiFetch('/duty/checklist?duty_type=LUNCH').catch(() => []),
      apiFetch('/duty/checklist?duty_type=CLEANING').catch(() => []),
    ]);
    const allItems = [...(lunch || []), ...(cleaning || [])];

    const renderGroup = (items, title, emoji, color) => items.length === 0 ? '' : `
      <div style="margin-bottom:20px">
        <div style="font-weight:700; font-size:14px; color:var(--text-sub); margin-bottom:10px">${emoji} ${title}</div>
        <div style="display:flex; flex-direction:column; gap:8px">
          ${items.map((t, i) => `
            <div style="display:flex; align-items:center; gap:12px; padding:12px 16px; background:var(--surface); border-radius:12px; border:1px solid var(--border)">
              <span style="font-size:16px; color:var(--text-muted); font-weight:700; min-width:20px">${i + 1}.</span>
              <div style="flex:1; font-weight:600">${t.text || t.title || '—'}</div>
              <span class="badge ${t.is_active ? 'badge-active' : 'badge-inactive'}">${t.is_active ? 'Активна' : 'Скрыта'}</span>
            </div>`).join('')}
        </div>
      </div>`;

    document.getElementById('dutyContent').innerHTML = `
      <div class="card">
        <div class="card-header">
          <div class="card-title">Задачи чеклиста</div>
        </div>
        ${!allItems.length
        ? '<p style="color:var(--text-muted); text-align:center; padding:20px">Нет задач</p>'
        : renderGroup(lunch || [], 'Обед', '🍽️', 'var(--primary)') +
        renderGroup(cleaning || [], 'Уборка', '🧹', 'var(--accent)')}
      </div>`;
  } catch (e) {
    document.getElementById('dutyContent').innerHTML = `<p style="color:var(--error); padding:20px">${e.message}</p>`;
  }
}

async function openAssignDutyModal() {
  try {
    const employees = await fetchAllUsers();
    const sel = document.getElementById('dutyEmployeeId');
    sel.innerHTML = '<option value="">— Выберите сотрудника —</option>' +
      employees.filter(e => e.status === 'ACTIVE' || e.status === 'WARNING').map(e => `<option value="${e.id}">${e.full_name}</option>`).join('');
    document.getElementById('dutyDate').value = new Date().toISOString().split('T')[0];
    document.getElementById('dutyTypeLunch').checked = true;
    updateDutyTypeStyle();
    openModal('assignDuty');
  } catch (e) { showToast(e.message, 'error'); }
}

function updateDutyTypeStyle() {
  const isLunch = document.getElementById('dutyTypeLunch').checked;
  document.getElementById('dutyTypeLunchLabel').style.borderColor = isLunch ? 'var(--primary)' : 'var(--border)';
  document.getElementById('dutyTypeLunchLabel').style.background = isLunch ? 'rgba(26,115,232,0.07)' : '';
  document.getElementById('dutyTypeCleaningLabel').style.borderColor = !isLunch ? 'var(--accent)' : 'var(--border)';
  document.getElementById('dutyTypeCleaningLabel').style.background = !isLunch ? 'rgba(0,200,83,0.07)' : '';
}

async function saveDutyAssignment() {
  const userId = document.getElementById('dutyEmployeeId').value;
  const date = document.getElementById('dutyDate').value;
  const dutyType = document.querySelector('input[name="dutyType"]:checked')?.value || 'LUNCH';
  if (!userId || !date) { showToast('Выберите сотрудника и дату', 'error'); return; }
  try {
    await apiFetch('/duty/assign', { method: 'POST', body: JSON.stringify({ user_id: userId, date, duty_type: dutyType }) });
    closeModal('assignDuty');
    showToast('Дежурный назначен', 'success');
    loadDutySchedule();
  } catch (e) { showToast(e.message, 'error'); }
}

async function verifyDuty(id, approve) {
  const note = approve ? '' : (prompt('Причина отклонения:') || '');
  try {
    await apiFetch(`/duty/${id}/verify`, {
      method: 'PATCH',
      body: JSON.stringify({ approve, ...(note ? { admin_note: note } : {}) })
    });
    showToast(approve ? 'Дежурство подтверждено' : 'Дежурство отклонено', 'success');
    loadDutySchedule();
  } catch (e) { showToast(e.message, 'error'); }
}

// =========== NEWS ===========
let editingNewsId = null;

async function loadNews() {
  try {
    const list = await apiFetch('/news') || [];
    const typeLabels = { general: 'Общее', announcement: 'Объявление', urgent: 'Срочно', system_update: 'Обновление' };
    const tbody = document.getElementById('newsTable');
    if (!list.length) {
      tbody.innerHTML = '<tr><td colspan="6" style="text-align:center; color:var(--text-muted); padding:32px">Нет новостей</td></tr>';
      return;
    }
    tbody.innerHTML = list.map(n => `
      <tr>
        <td>
          <div style="display:flex; align-items:center; gap:10px">
            ${n.image_url ? `<img src="${n.image_url.startsWith('http') ? n.image_url : API.replace('/api/v1', '') + n.image_url}" style="width:40px;height:40px;object-fit:cover;border-radius:8px;border:1px solid var(--border)">` : ''}
            <div>
              <div style="font-weight:700">${n.title}</div>
              <div style="font-size:12px; color:var(--text-sub); max-width:280px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis">${n.content}</div>
            </div>
          </div>
        </td>
        <td>${typeLabels[n.type] || n.type}</td>
        <td>${n.pinned ? '<span class="badge badge-completed">📌 Закреплено</span>' : '—'}</td>
        <td>
          <button class="btn btn-ghost btn-sm" onclick="loadNewsStats('${n.id}', this)">Показать</button>
        </td>
        <td style="color:var(--text-sub)">${n.created_at ? new Date(n.created_at).toLocaleDateString('ru-RU') : '—'}</td>
        <td style="display:flex; gap:6px; flex-wrap:wrap">
          <button class="btn btn-ghost btn-sm" onclick="editNews('${n.id}', ${JSON.stringify(n).replace(/"/g, '&quot;')})" style="color:var(--primary); border-color:var(--primary)">✏️</button>
          <button class="btn btn-ghost btn-sm" onclick="toggleNewsPin('${n.id}')" style="color:var(--warning); border-color:var(--warning)">${n.pinned ? '📌' : '📍'}</button>
          <button class="btn btn-danger btn-sm" onclick="deleteNews('${n.id}')">🗑</button>
        </td>
      </tr>
    `).join('');
  } catch (e) { showToast(e.message, 'error'); }
}

async function loadNewsStats(newsId, btn) {
  try {
    const s = await apiFetch(`/news/${newsId}/stats`);
    btn.textContent = `${s.read_count}/${s.total_employees}`;
    btn.disabled = true;
  } catch (_) { }
}

function openAddNewsModal() {
  editingNewsId = null;
  document.getElementById('newsModalTitle').textContent = 'Создать новость';
  document.getElementById('newsTitle').value = '';
  document.getElementById('newsContent').value = '';
  document.getElementById('newsType').value = 'general';
  document.getElementById('newsPinned').checked = false;
  document.getElementById('newsImageUrl').value = '';
  document.getElementById('newsImagePreview').style.display = 'none';
  document.getElementById('newsImageFile').value = '';
  document.getElementById('newsUploadBtn').style.display = 'none';
  openModal('addNews');
}

function editNews(id, news) {
  editingNewsId = id;
  document.getElementById('newsModalTitle').textContent = 'Редактировать новость';
  document.getElementById('newsTitle').value = news.title || '';
  document.getElementById('newsContent').value = news.content || '';
  document.getElementById('newsType').value = news.type || 'general';
  document.getElementById('newsPinned').checked = !!news.pinned;
  document.getElementById('newsImageUrl').value = news.image_url || '';
  document.getElementById('newsImageFile').value = '';
  document.getElementById('newsUploadBtn').style.display = 'none';
  if (news.image_url) {
    const src = news.image_url.startsWith('http') ? news.image_url : API.replace('/api/v1', '') + news.image_url;
    document.getElementById('newsImagePreviewImg').src = src;
    document.getElementById('newsImagePreview').style.display = '';
    document.getElementById('newsImageStatus').textContent = 'Текущее фото';
  } else {
    document.getElementById('newsImagePreview').style.display = 'none';
  }
  openModal('addNews');
}

function previewNewsImage(input) {
  const file = input.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = (e) => {
    document.getElementById('newsImagePreviewImg').src = e.target.result;
    document.getElementById('newsImagePreview').style.display = '';
    document.getElementById('newsImageStatus').textContent = 'Нажмите «Загрузить» чтобы сохранить фото';
    document.getElementById('newsUploadBtn').style.display = '';
  };
  reader.readAsDataURL(file);
}

async function uploadNewsImage() {
  const file = document.getElementById('newsImageFile').files[0];
  if (!file) return;
  const formData = new FormData();
  formData.append('file', file);
  try {
    document.getElementById('newsImageStatus').textContent = 'Загрузка...';
    const r = await fetch(`${API}/news/upload-image`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}` },
      body: formData
    });
    if (!r.ok) { const d = await r.json(); throw new Error(d.detail || 'Ошибка загрузки'); }
    const data = await r.json();
    document.getElementById('newsImageUrl').value = data.image_url;
    document.getElementById('newsImageStatus').textContent = '✅ Фото загружено';
    document.getElementById('newsUploadBtn').style.display = 'none';
    showToast('Фото загружено', 'success');
  } catch (e) {
    document.getElementById('newsImageStatus').textContent = '❌ ' + e.message;
    showToast(e.message, 'error');
  }
}

async function saveNews() {
  const title = document.getElementById('newsTitle').value.trim();
  const content = document.getElementById('newsContent').value.trim();
  if (!title || !content) { showToast('Заполните заголовок и текст', 'error'); return; }
  const payload = {
    title,
    content,
    type: document.getElementById('newsType').value,
    pinned: document.getElementById('newsPinned').checked,
    target_audience: 'all',
    image_url: document.getElementById('newsImageUrl').value || null,
  };
  try {
    if (editingNewsId) {
      await apiFetch(`/news/${editingNewsId}`, { method: 'PUT', body: JSON.stringify(payload) });
      showToast('Новость обновлена', 'success');
    } else {
      await apiFetch('/news', { method: 'POST', body: JSON.stringify(payload) });
      showToast('Новость создана', 'success');
    }
    closeModal('addNews');
    loadNews();
  } catch (e) { showToast(e.message, 'error'); }
}

async function deleteNews(id) {
  if (!confirm('Удалить новость?')) return;
  try {
    await apiFetch(`/news/${id}`, { method: 'DELETE' });
    showToast('Новость удалена', 'success');
    loadNews();
  } catch (e) { showToast(e.message, 'error'); }
}

async function toggleNewsPin(id) {
  try {
    await apiFetch(`/news/${id}/pin`, { method: 'PATCH' });
    showToast('Закрепление изменено', 'success');
    loadNews();
  } catch (e) { showToast(e.message, 'error'); }
}

// =========== SCHEDULE ===========
async function loadScheduleEmployeeList() {
  try {
    const employees = await fetchAllUsers();
    const sel = document.getElementById('scheduleEmpSelect');
    const active = employees.filter(e => e.status === 'ACTIVE');
    sel.innerHTML = '<option value="">— Выберите сотрудника —</option>' +
      active.map(e => `<option value="${e.id}">${e.full_name} (${e.team_name || '—'})</option>`).join('');
  } catch (e) { showToast(e.message, 'error'); }
}

async function loadEmployeeSchedule() {
  const userId = document.getElementById('scheduleEmpSelect').value;
  if (!userId) return;
  try {
    const list = await apiFetch(`/employee-schedules/employee/${userId}`) || [];
    const dayNames = ['Понедельник', 'Вторник', 'Среда', 'Четверг', 'Пятница', 'Суббота', 'Воскресенье'];
    const scheduleMap = {};
    list.forEach(d => { scheduleMap[d.day_of_week] = d; });

    document.getElementById('scheduleContent').innerHTML = `
      <div class="card">
        <div class="card-header">
          <div class="card-title">Расписание сотрудника</div>
          <button class="btn btn-primary btn-sm" onclick="saveAllSchedule('${userId}')">💾 Сохранить</button>
        </div>
        <div style="display:flex; flex-direction:column; gap:12px" id="scheduleRows">
          ${[0, 1, 2, 3, 4, 5, 6].map(d => {
      const day = scheduleMap[d];
      const isWork = day ? day.is_working_day : d < 5;
      const start = day?.start_time ? day.start_time.slice(0, 5) : '09:00';
      const end = day?.end_time ? day.end_time.slice(0, 5) : '18:00';
      return `
              <div style="display:grid; grid-template-columns:140px 120px 1fr; align-items:center; gap:16px; padding:14px 16px; background:var(--surface); border-radius:12px; border:1px solid var(--border)">
                <div style="font-weight:700">${dayNames[d]}</div>
                <label style="display:flex; align-items:center; gap:8px; font-size:13px; font-weight:700; cursor:pointer">
                  <input type="checkbox" id="sched_work_${d}" ${isWork ? 'checked' : ''} onchange="toggleScheduleDay(${d})">
                  Рабочий
                </label>
                <div id="sched_times_${d}" style="display:${isWork ? 'flex' : 'none'}; gap:10px; align-items:center">
                  <input type="time" id="sched_start_${d}" value="${start}" class="filter-input" style="width:120px">
                  <span style="color:var(--text-sub)">—</span>
                  <input type="time" id="sched_end_${d}" value="${end}" class="filter-input" style="width:120px">
                </div>
              </div>`;
    }).join('')}
        </div>
      </div>`;
  } catch (e) {
    document.getElementById('scheduleContent').innerHTML = `<p style="color:var(--error); padding:20px">${e.message}</p>`;
  }
}

function toggleScheduleDay(d) {
  const isWork = document.getElementById(`sched_work_${d}`).checked;
  document.getElementById(`sched_times_${d}`).style.display = isWork ? 'flex' : 'none';
}

async function saveAllSchedule(userId) {
  const days = [];
  for (let d = 0; d <= 6; d++) {
    const isWork = document.getElementById(`sched_work_${d}`)?.checked;
    const start = document.getElementById(`sched_start_${d}`)?.value;
    const end = document.getElementById(`sched_end_${d}`)?.value;
    if (isWork && start && end) {
      const [sh, sm] = start.split(':').map(Number);
      const [eh, em] = end.split(':').map(Number);
      const dur = (eh * 60 + em) - (sh * 60 + sm);
      if (dur < 360) { showToast(`${['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'][d]}: рабочий день не менее 6 часов`, 'error'); return; }
    }
    days.push({ day_of_week: d, is_working_day: !!isWork, start_time: isWork ? start : null, end_time: isWork ? end : null });
  }
  try {
    for (const day of days) {
      await apiFetch(`/employee-schedules/user/${userId}`, { method: 'POST', body: JSON.stringify(day) });
    }
    showToast('Расписание сохранено', 'success');
  } catch (e) { showToast(e.message, 'error'); }
}

// =========== HELPERS ===========
function statusBadge(s) {
  const map = {
    present: ['badge-present', '✅ В офисе'],
    late: ['badge-late', '⚠️ Опоздание'],
    absent: ['badge-absent', '❌ Не пришёл'],
    incomplete: ['badge-incomplete', '🕒 Не завершил день'],
    completed: ['badge-completed', '✔️ Завершён'],
    manual: ['badge-manual', '✏️ Вручную'],
    approved_absence: ['badge-approved-absence', '✓ Разреш. отсутствие'],
    early_leave: ['badge-early-leave', '🏃 Ранний уход'],
    overtime: ['badge-overtime', '⏰ Сверхурочно'],
  };

  if (!s) return '<span class="badge badge-absent">—</span>';
  const [cls, lbl] = map[s.toLowerCase()] || ['badge-manual', s];
  return `<span class="badge ${cls}">${lbl}</span>`;
}

function openModal(name) {
  document.getElementById('modal-' + name).classList.add('open');
}

function closeModal(name) {
  document.getElementById('modal-' + name).classList.remove('open');
}

function showToast(msg, type = 'success') {
  const t = document.getElementById('toast');
  const asText = (() => {
    if (msg == null) return '';
    if (typeof msg === 'string') return msg;
    if (msg instanceof Error) return msg.message || String(msg);
    try { return JSON.stringify(msg); } catch (_) { return String(msg); }
  })();
  t.textContent = (type === 'success' ? '✅ ' : '❌ ') + asText;
  t.className = `toast ${type} show`;
  setTimeout(() => t.classList.remove('show'), 3000);
}

// Close modal on backdrop click
document.querySelectorAll('.modal-overlay').forEach(el => {
  el.addEventListener('click', e => { if (e.target === el) el.classList.remove('open'); });
});

// Enter key on login
document.getElementById('loginPassword').addEventListener('keydown', e => {
  if (e.key === 'Enter') doLogin();
});

// =========== AUDIT LOG ===========
async function loadAuditLog() {
  const search = (document.getElementById('auditSearch')?.value || '').trim();
  const action = document.getElementById('auditAction')?.value || '';
  const dateFrom = document.getElementById('auditDateFrom')?.value || '';
  const dateTo = document.getElementById('auditDateTo')?.value || '';

  const params = new URLSearchParams();
  if (action) params.append('action', action);
  if (dateFrom) params.append('date_from', dateFrom);
  if (dateTo) params.append('date_to', dateTo);
  params.append('limit', '100');

  const tbody = document.getElementById('auditLogTable');
  tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-muted);padding:32px">Загрузка...</td></tr>';

  try {
    const data = await apiFetch(`/audit-logs?${params.toString()}`);
    const logs = Array.isArray(data) ? data : (data.items || []);

    if (!logs.length) {
      tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-muted);padding:32px">Нет записей</td></tr>';
      return;
    }

    // Фильтрация по поиску на клиенте (по action/entity)
    const filtered = search
      ? logs.filter(l =>
        (l.action || '').toLowerCase().includes(search.toLowerCase()) ||
        (l.entity || '').toLowerCase().includes(search.toLowerCase())
      )
      : logs;

    tbody.innerHTML = filtered.map(log => {
      const ts = log.created_at ? new Date(log.created_at).toLocaleString('ru-RU') : '—';
      const actor = log.actor_name || log.actor_id || '—';
      const newVal = formatAuditDetail(log.new_value);
      return `<tr>
        <td style="white-space:nowrap;font-size:12px">${ts}</td>
        <td>${escHtml(actor)}</td>
        <td><span class="badge" style="background:rgba(24,119,242,.1);color:var(--primary);font-size:11px;padding:2px 8px;border-radius:6px">${escHtml(log.action || '—')}</span></td>
        <td style="font-size:12px">${escHtml(log.entity || '—')} ${log.entity_id ? '<span style="opacity:.5;font-size:10px">' + String(log.entity_id).slice(0, 8) + '…</span>' : ''}</td>
        <td style="font-size:11px;color:var(--text-sub);max-width:300px">${newVal}</td>
      </tr>`;
    }).join('');
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="5" style="text-align:center;color:var(--danger);padding:32px">${escHtml(e.message)}</td></tr>`;
  }
}

function escHtml(str) {
  if (!str) return '';
  return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function formatAuditDetail(val) {
  if (val == null) return '—';
  let obj = val;
  if (typeof val === 'string') {
    try { obj = JSON.parse(val); } catch (_) { return escHtml(String(val).slice(0, 120)); }
  }
  if (typeof obj === 'object' && !Array.isArray(obj)) {
    return Object.entries(obj)
      .filter(([, v]) => v != null && v !== '')
      .map(([k, v]) => `<span style="color:var(--text-muted)">${escHtml(k)}:</span> <b>${escHtml(String(v))}</b>`)
      .join(' &nbsp;·&nbsp; ');
  }
  return escHtml(JSON.stringify(obj).slice(0, 120));
}

// ── Global search (filters visible table rows by name) ───────────────────────
function handleGlobalSearch(query) {
  const q = query.toLowerCase().trim();

  // Если мы на странице сотрудников, вызываем специальный фильтр
  if (document.getElementById('page-employees').classList.contains('active')) {
    filterEmployees();
    return;
  }

  document.querySelectorAll('tbody tr').forEach(row => {
    row.style.display = q && !row.textContent.toLowerCase().includes(q) ? 'none' : '';
  });
}

// Init
if (accessToken) {
  document.getElementById('loginPage').style.display = 'none';
  initApp();
}

// Mobile sidebar toggle
function toggleSidebar() {
  document.querySelector('.sidebar').classList.toggle('open');
  document.getElementById('sidebarOverlay').classList.toggle('open');
}

// Show mobile header after login
function showMobileHeader(username) {
  if (window.innerWidth <= 768) {
    document.getElementById('mobileHeader').style.display = 'flex';
    document.getElementById('mobileUser').textContent = username || '';
  }
}

// Check screen size and toggle mobile elements
window.addEventListener('resize', function() {
  if (window.innerWidth <= 768) {
    document.getElementById('mobileHeader').style.display = 'flex';
  } else {
    document.getElementById('mobileHeader').style.display = 'none';
    document.querySelector('.sidebar').classList.remove('open');
    document.getElementById('sidebarOverlay').classList.remove('open');
  }
});

// Initial check
if (window.innerWidth <= 768) {
  document.getElementById('mobileHeader').style.display = 'flex';
}

// Close sidebar when clicking a nav item on mobile
document.querySelectorAll('.sidebar-item').forEach(item => {
  item.addEventListener('click', function() {
    if (window.innerWidth <= 768) {
      toggleSidebar();
    }
  });
});

// ============ QR Scanner for Admin ============
let qrScanStream = null;

function openQRScanModal() {
  document.getElementById('qrManualToken').value = '';
  document.getElementById('startQRScanBtn').style.display = 'block';
  document.getElementById('qrScanVideo').innerHTML = '<div style="text-align:center"><p style="margin-bottom:8px">Камера недоступна</p><p style="font-size:12px; color:#888">Нажмите кнопку ниже для старта</p></div>';
  openModal('qrScan');
}

async function startQRScan() {
  const video = document.getElementById('qrScanVideo');
  const btn = document.getElementById('startQRScanBtn');

  try {
    qrScanStream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
    video.innerHTML = '';
    const videoEl = document.createElement('video');
    videoEl.style.width = '100%';
    videoEl.style.height = '100%';
    videoEl.style.objectFit = 'cover';
    videoEl.srcObject = qrScanStream;
    videoEl.play();
    video.appendChild(videoEl);
    btn.style.display = 'none';

    // Simple scan - just show message that camera is running
    showToast('Камера работает! Введите токен вручную или используйте сканер', 'info');
  } catch (e) {
    showToast('Не удалось получить доступ к камере: ' + e.message, 'error');
  }
}

async function submitQRScan() {
  const token = document.getElementById('qrManualToken').value.trim();
  if (!token) return showToast('Введите токен QR-кода', 'error');

  // Stop camera if running
  if (qrScanStream) {
    qrScanStream.getTracks().forEach(track => track.stop());
    qrScanStream = null;
  }

  try {
    showToast('Отмечаем...', 'info');
    const res = await apiFetch('/attendance/check-in', {
      method: 'POST',
      body: JSON.stringify({ qr_token: token })
    });

    if (res && res.check_in_time) {
      showToast('✅ Приход отмечен в ' + res.check_in_time.slice(0, 5), 'success');
      closeModal('qrScan');
    }
  } catch (e) {
    // If check-in fails, try check-out
    try {
      const res2 = await apiFetch('/attendance/check-out', {
        method: 'POST',
        body: JSON.stringify({ qr_token: token })
      });
      if (res2 && res2.check_out_time) {
        showToast('✅ Уход отмечен в ' + res2.check_out_time.slice(0, 5), 'success');
        closeModal('qrScan');
      }
    } catch (e2) {
      showToast('Ошибка: ' + (e.message || e2.message), 'error');
    }
  }
}

// Close QR scan modal cleanup
document.getElementById('modal-qrScan').addEventListener('click', function(e) {
  if (e.target === this && qrScanStream) {
    qrScanStream.getTracks().forEach(track => track.stop());
    qrScanStream = null;
  }
});
