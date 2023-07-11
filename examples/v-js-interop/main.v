import webview
import json
import rand
import net.http
import time

struct App {
	w &webview.Webview
mut:
	settings struct {
	mut:
		toggle bool
	}
}

struct News {
	title string
	body  string
}

// Calls JS from V.
fn connect(event_id &char, args &char, app &App) {
	app.w.eval("console.log('Hello from V!');")
	app.w.eval('init(${json.encode(app.settings)});')
}

// Returns a value when it's called from JS.
// (We can use `_` to ignore unused parameters in the C callback.)
fn toggle(event_id &char, _ &char, mut app App) {
	app.settings.toggle = !app.settings.toggle
	dump(app.settings.toggle)
	app.w.result(event_id, json.encode(app.settings.toggle))
}

// Handles received arguments.
fn login(event_id &char, raw_args &char, mut app App) {
	// `args`(here `raw_args`) initially is a JSON array of all arguments passed to the JS function.
	mut resp := 'An error occured.'
	defer {
		app.w.result(event_id, json.encode(resp))
	}
	// Use the json module to handle decoding into the expected type.
	args := json.decode([]string, unsafe { raw_args.vstring() }) or { return }
	name := args[0] or { return }
	resp = 'Data received: Check your terminal.'
	println('Hello ${name}!')
}

// Spawns a thread and returns the functions result from it.
// This helps to avoid interferences with the UI when calling a function that can take some time to process
// (E.g., it allows to keep updating the content and animations running in the meantime).
// Let's refer to this as async example.
fn fetch_news(event_id &char, _ &char, app &App) {
	// With GC enabled:
	// Deref the event_id to keep it available when executing `webview.result` from the spawned thread.
	// Otherwise it gets obscured during garbage collection and using it in a `webview.result` won't
	// return data to the calling JS function.
	spawn app.fetch_news(*event_id)
}

fn (app &App) fetch_news(event_id &char) {
	mut result := News{}
	defer {
		// Artificially delay the result to simulate a function that does some extended processing.
		time.sleep(time.second * 3)
		app.w.result(event_id, json.encode(result))
	}

	resp := http.get('https://jsonplaceholder.typicode.com/posts') or {
		eprintln('Failed fetching news.')
		return
	}
	news := json.decode([]News, resp.body) or {
		eprintln('Failed decoding news.')
		return
	}
	result = news[rand.int_in_range(0, news.len - 1) or { return }]
}

fn main() {
	mut app := App{
		w: webview.create(debug: true)
		settings: struct {true}
	}
	app.w.set_size(800, 600, .@none)
	// The first string arg names the functions for JS usage. E.g. use JS's `camelCase` convention if you prefer it.
	app.w.bind('connect', connect, &app)
	app.w.bind('toggle_setting', toggle, &app)
	app.w.bind('login', login, &app)
	app.w.bind('fetch_news', fetch_news, &app)
	app.w.navigate('file://${@VMODROOT}/index.html')
	app.w.run()
	app.w.destroy()
}
