// Changes data on the server as an administrator, outside the app.
// The flows use it to check that the app follows Realtime events.
//
// Env: SUPABASE_URL, KEY (secret key), ACTION, and the values that the action reads.

var base = SUPABASE_URL + '/rest/v1'
var headers = {
  apikey: KEY,
  'Content-Type': 'application/json',
  Prefer: 'return=representation',
}

function send(method, path, body) {
  var response = http.request(base + path, {
    method: method,
    headers: headers,
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!response.ok) {
    throw new Error(method + ' ' + path + ' failed: ' + response.status + ' ' + response.body)
  }
  var rows = json(response.body)
  if (rows.length === 0) {
    throw new Error(method + ' ' + path + ' changed no rows')
  }
  return rows
}

function eq(value) {
  return 'eq.' + encodeURIComponent(value)
}

if (ACTION === 'insert_reminder') {
  var list = send('GET', '/lists?name=' + eq(LIST))[0]
  send('POST', '/reminders', { list_id: list.id, title: TITLE })
} else if (ACTION === 'rename_reminder') {
  send('PATCH', '/reminders?title=' + eq(TITLE), { title: NEW_TITLE })
} else if (ACTION === 'delete_reminder') {
  send('DELETE', '/reminders?title=' + eq(TITLE))
} else if (ACTION === 'rename_list') {
  send('PATCH', '/lists?name=' + eq(LIST), { name: NEW_NAME })
} else if (ACTION === 'delete_list') {
  send('DELETE', '/lists?name=' + eq(LIST))
} else if (ACTION === 'remove_member') {
  var profile = send('GET', '/profiles?email=' + eq(EMAIL))[0]
  send('DELETE', '/list_members?user_id=' + eq(profile.id))
} else if (ACTION === 'complete_reminder') {
  send('PATCH', '/reminders?title=' + eq(TITLE), { completed_at: new Date().toISOString() })
} else if (ACTION === 'assert_reminder') {
  // Checks the notes and the completed state of a reminder on the server.
  // The app shows an update before the server has it, so the first reads can be early.
  var saved
  for (var attempt = 0; attempt < 100; attempt++) {
    saved = send('GET', '/reminders?title=' + eq(TITLE))[0]
    if (saved.notes === NOTES) break
  }
  if (saved.notes !== NOTES) {
    throw new Error('Expected notes "' + NOTES + '", found "' + saved.notes + '"')
  }
  if ((saved.completed_at !== null) !== (COMPLETED === 'true')) {
    throw new Error('Expected completed=' + COMPLETED + ', found completed_at=' + saved.completed_at)
  }
} else if (ACTION === 'hide_reminder') {
  // Moves a reminder to a list of a new user, as a member of a shared list can do.
  // The app user cannot read that list.
  var created = http.post(SUPABASE_URL + '/auth/v1/admin/users', {
    headers: { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: OTHER_EMAIL, password: 'password123', email_confirm: true }),
  })
  if (!created.ok) {
    throw new Error('Create user failed: ' + created.status + ' ' + created.body)
  }
  var hidden = send('POST', '/lists', { name: 'Hidden', owner_id: json(created.body).id })[0]
  send('PATCH', '/reminders?title=' + eq(TITLE), { list_id: hidden.id })
} else if (ACTION === 'assert_object_folders') {
  // Each reminder with images has one folder in the bucket.
  var response = http.post(SUPABASE_URL + '/storage/v1/object/list/attachments', {
    headers: { apikey: KEY, Authorization: 'Bearer ' + KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefix: '', limit: 100 }),
  })
  if (!response.ok) {
    throw new Error('Storage list failed: ' + response.status + ' ' + response.body)
  }
  var folders = json(response.body)
  if (folders.length !== Number(EXPECTED)) {
    throw new Error('Expected ' + EXPECTED + ' folders in the bucket, found ' + folders.length)
  }
} else {
  throw new Error('Unknown ACTION: ' + ACTION)
}
