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
} else {
  throw new Error('Unknown ACTION: ' + ACTION)
}
