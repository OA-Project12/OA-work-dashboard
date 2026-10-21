import { useEffect, useMemo, useState } from 'react'

const people = [
  { id: 'me', name: 'Nicha K.', initials: 'NK', color: 'violet' },
  { id: 'ton', name: 'Ton Chai', initials: 'TC', color: 'mint' },
  { id: 'may', name: 'May R.', initials: 'MR', color: 'peach' },
  { id: 'pim', name: 'Pimchanok', initials: 'PM', color: 'blue' },
]

const columns = [
  { id: 'backlog', name: 'Backlog', tone: 'slate' },
  { id: 'progress', name: 'In progress', tone: 'amber' },
  { id: 'review', name: 'In review', tone: 'violet' },
  { id: 'done', name: 'Done', tone: 'green' },
]

const seedTasks = [
  { id: 't1', title: 'Map the onboarding journey', description: 'Review the first-run experience and capture friction points before the next design review.', column: 'progress', labels: ['Product', 'Research'], due: '2026-10-23', members: ['me', 'may'], comments: [{ author: 'May R.', text: 'I added the interview notes to the shared folder.', time: '10:24' }], activity: ['Nicha moved this card to In progress', 'May added an update'], checklist: '2/4' },
  { id: 't2', title: 'Prepare Q4 campaign brief', description: 'Bring the channel plan, key dates, and creative direction together in one concise brief.', column: 'backlog', labels: ['Marketing'], due: '2026-10-28', members: ['ton'], comments: [], activity: ['Ton created this card'], checklist: '0/3' },
  { id: 't3', title: 'Polish dashboard empty states', description: 'Give first-time users a clear next step when their workspace has no data yet.', column: 'review', labels: ['Design', 'Product'], due: '2026-10-21', members: ['me', 'pim'], comments: [{ author: 'Pimchanok', text: 'Ready for a quick review ✨', time: '09:12' }], activity: ['Pimchanok moved this card to In review'], checklist: '3/3' },
  { id: 't4', title: 'Audit mobile navigation', description: 'Check touch targets, focus order, and overflow on compact screens.', column: 'backlog', labels: ['Design'], due: '2026-10-30', members: ['may'], comments: [], activity: ['May created this card'], checklist: '1/5' },
  { id: 't5', title: 'Share weekly progress with the team', description: 'Post a short update with decisions, risks, and priorities for next week.', column: 'done', labels: ['Operations'], due: '2026-10-20', members: ['ton', 'me'], comments: [], activity: ['Nicha completed this card'], checklist: '2/2' },
  { id: 't6', title: 'Define card detail permissions', description: 'Confirm how observers and guests can view, comment, and edit shared work.', column: 'progress', labels: ['Product', 'Operations'], due: '2026-10-25', members: ['pim'], comments: [], activity: ['Pimchanok assigned this card to themself'], checklist: '1/3' },
  { id: 't7', title: 'Review the launch checklist', description: 'Make sure the launch checklist is complete and owners are clear.', column: 'review', labels: ['Marketing'], due: '2026-10-27', members: ['ton', 'may'], comments: [], activity: ['Ton added a checklist'], checklist: '5/6' },
]

const labelColors = { Product: 'lilac', Research: 'blue', Marketing: 'peach', Design: 'pink', Operations: 'green' }
const STORAGE_KEY = 'orbit-react-board-v1'

function readTasks() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY)
    return saved ? JSON.parse(saved) : seedTasks
  } catch {
    return seedTasks
  }
}

function Icon({ name, size = 18 }) {
  const paths = {
    grid: <><rect x="3" y="3" width="7" height="7" rx="1.4"/><rect x="14" y="3" width="7" height="7" rx="1.4"/><rect x="3" y="14" width="7" height="7" rx="1.4"/><rect x="14" y="14" width="7" height="7" rx="1.4"/></>,
    search: <><circle cx="10.8" cy="10.8" r="6.8"/><path d="m16 16 4.4 4.4"/></>,
    bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M10 21h4"/></>,
    plus: <><path d="M12 5v14M5 12h14"/></>,
    filter: <><path d="M4 6h16M7 12h10m-7 6h4"/></>,
    calendar: <><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 10h18"/></>,
    comment: <><path d="M20 11.5a7.5 7.5 0 0 1-8 7.5 8.6 8.6 0 0 1-3.6-.8L4 20l1.2-3.7A7.1 7.1 0 0 1 4 12c0-4.2 3.6-7.5 8-7.5s8 2.8 8 7Z"/></>,
    check: <path d="m5 12 4 4L19 6"/>,
    close: <><path d="m6 6 12 12M18 6 6 18"/></>,
    dots: <><circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/></>,
    arrow: <><path d="M5 12h14M13 6l6 6-6 6"/></>,
    chevron: <path d="m8 10 4 4 4-4"/>,
    board: <><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M9 4v16M15 4v16"/></>,
  }
  return <svg aria-hidden="true" width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{paths[name] || paths.grid}</svg>
}

function Avatar({ person, small = false }) {
  return <span className={`avatar ${person?.color || 'violet'} ${small ? 'avatar-small' : ''}`} title={person?.name}>{person?.initials || '?'}</span>
}

function Avatars({ memberIds = [] }) {
  const assigned = memberIds.map(id => people.find(person => person.id === id)).filter(Boolean)
  return <span className="avatar-stack">{assigned.slice(0, 3).map(person => <Avatar key={person.id} person={person} small />)}{assigned.length > 3 && <span className="avatar-more">+{assigned.length - 3}</span>}</span>
}

function dueLabel(date) {
  if (!date) return null
  const today = new Date()
  today.setHours(12, 0, 0, 0)
  const due = new Date(`${date}T12:00:00`)
  const days = Math.round((due - today) / 86400000)
  const formatted = new Intl.DateTimeFormat('en', { month: 'short', day: 'numeric' }).format(due)
  return { text: days === 0 ? 'Today' : days === 1 ? 'Tomorrow' : formatted, state: days < 0 ? 'overdue' : days < 2 ? 'soon' : 'normal' }
}

function TaskCard({ task, onOpen }) {
  const due = dueLabel(task.due)
  return <button className="task-card" onClick={() => onOpen(task)} aria-label={`Open task: ${task.title}`}>
    <span className="task-labels">{task.labels.slice(0, 2).map(label => <span className={`label ${labelColors[label] || 'lilac'}`} key={label}>{label}</span>)}</span>
    <span className="task-title">{task.title}</span>
    {task.description && <span className="task-description">{task.description}</span>}
    <span className="task-meta">
      {due && <span className={`meta-item ${due.state}`}><Icon name="calendar" size={14}/>{due.text}</span>}
      {Number(task.checklist?.split('/')[0]) > 0 && <span className="meta-item"><Icon name="check" size={14}/>{task.checklist}</span>}
      {task.comments.length > 0 && <span className="meta-item"><Icon name="comment" size={14}/>{task.comments.length}</span>}
      <Avatars memberIds={task.members}/>
    </span>
  </button>
}

function TaskDialog({ task, columns: boardColumns, onClose, onSave, onDelete, canDelete }) {
  const [draft, setDraft] = useState(() => task ? structuredClone(task) : { title: '', description: '', column: boardColumns[0]?.id, labels: [], due: '', members: [], comments: [], activity: [], checklist: '0/0' })
  const [comment, setComment] = useState('')
  const editing = Boolean(task)
  const update = (key, value) => setDraft(current => ({ ...current, [key]: value }))
  const toggleMember = id => update('members', draft.members.includes(id) ? draft.members.filter(member => member !== id) : [...draft.members, id])
  const addComment = () => {
    if (!comment.trim()) return
    update('comments', [...draft.comments, { author: 'Nicha K.', text: comment.trim(), time: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }) }])
    setComment('')
  }
  const save = event => {
    event.preventDefault()
    if (!draft.title.trim()) return
    onSave({ ...draft, title: draft.title.trim(), activity: [...draft.activity, editing ? 'Nicha updated this task' : 'Nicha created this task'] })
  }

  return <div className="dialog-scrim" onMouseDown={event => event.target === event.currentTarget && onClose()}>
    <section className="dialog" role="dialog" aria-modal="true" aria-labelledby="dialog-title">
      <header className="dialog-header"><div><p className="eyebrow">{editing ? 'TASK DETAILS' : 'NEW TASK'}</p><h2 id="dialog-title">{editing ? 'Keep the team in sync' : 'Add a task to the board'}</h2></div><button className="icon-button" onClick={onClose} aria-label="Close dialog"><Icon name="close"/></button></header>
      <form onSubmit={save}>
        <div className="dialog-content">
          <div className="dialog-main">
            <label className="form-label" htmlFor="task-title">Task name</label>
            <input id="task-title" className="text-input title-input" autoFocus value={draft.title} onChange={event => update('title', event.target.value)} placeholder="What needs to get done?" required />
            <label className="form-label spaced" htmlFor="task-description">Description</label>
            <textarea id="task-description" className="text-input description-input" value={draft.description} onChange={event => update('description', event.target.value)} placeholder="Add context, links, or a clear definition of done…" />
            <div className="section-heading"><span>Activity</span><span className="section-count">{draft.comments.length + draft.activity.length}</span></div>
            <div className="activity-list">
              {[...draft.comments.map(item => ({ ...item, kind: 'comment' })), ...draft.activity.map(item => ({ text: item, author: 'Nicha K.', time: 'Earlier', kind: 'activity' }))].slice(-5).reverse().map((item, index) => <div className="activity-item" key={`${item.time}-${index}`}><Avatar person={people[0]} small/><div><p><strong>{item.author}</strong> {item.kind === 'activity' ? item.text.replace('Nicha ', '') : 'commented'}</p>{item.kind === 'comment' && <blockquote>{item.text}</blockquote>}<time>{item.time}</time></div></div>)}
              {draft.comments.length + draft.activity.length === 0 && <p className="muted-small">No activity yet. Start the conversation below.</p>}
            </div>
            <div className="comment-entry"><Avatar person={people[0]} small/><input className="text-input" value={comment} onChange={event => setComment(event.target.value)} onKeyDown={event => event.key === 'Enter' && !event.shiftKey && (event.preventDefault(), addComment())} placeholder="Write a comment…" aria-label="Write a comment"/><button type="button" className="send-button" onClick={addComment} disabled={!comment.trim()} aria-label="Post comment"><Icon name="arrow"/></button></div>
          </div>
          <aside className="dialog-side">
            <div className="side-field"><label className="form-label" htmlFor="task-column">List</label><select id="task-column" className="text-input" value={draft.column} onChange={event => update('column', event.target.value)}>{boardColumns.map(column => <option key={column.id} value={column.id}>{column.name}</option>)}</select></div>
            <div className="side-field"><span className="form-label">Due date</span><input className="text-input" type="date" value={draft.due || ''} onChange={event => update('due', event.target.value)} aria-label="Due date"/></div>
            <div className="side-field"><span className="form-label">Members</span><div className="member-picker">{people.map(person => <label className={`member-option ${draft.members.includes(person.id) ? 'selected' : ''}`} key={person.id}><input type="checkbox" checked={draft.members.includes(person.id)} onChange={() => toggleMember(person.id)}/><Avatar person={person} small/><span>{person.name}</span>{draft.members.includes(person.id) && <Icon name="check" size={15}/>}</label>)}</div></div>
            <div className="side-field"><span className="form-label">Labels</span><div className="label-picker">{Object.keys(labelColors).map(label => <label className={`label-choice ${draft.labels.includes(label) ? 'selected' : ''}`} key={label}><input type="checkbox" checked={draft.labels.includes(label)} onChange={() => update('labels', draft.labels.includes(label) ? draft.labels.filter(item => item !== label) : [...draft.labels, label])}/><span className={`label ${labelColors[label]}`}>{label}</span></label>)}</div></div>
          </aside>
        </div>
        <footer className="dialog-footer">{editing && canDelete ? <button type="button" className="delete-button" onClick={() => onDelete(task.id)}>Delete task</button> : <span/>}<div><button type="button" className="button secondary" onClick={onClose}>Cancel</button><button className="button primary" type="submit">{editing ? 'Save changes' : 'Create task'}</button></div></footer>
      </form>
    </section>
  </div>
}

function App() {
  const [tasks, setTasks] = useState(readTasks)
  const [boardColumns, setBoardColumns] = useState(columns)
  const [search, setSearch] = useState('')
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [memberFilter, setMemberFilter] = useState('')
  const [labelFilter, setLabelFilter] = useState('')
  const [dueFilter, setDueFilter] = useState('')
  const [dialogTask, setDialogTask] = useState(null)
  const [creating, setCreating] = useState(false)
  const [notificationsOpen, setNotificationsOpen] = useState(false)
  const [notice, setNotice] = useState('')
  const [mobileNavOpen, setMobileNavOpen] = useState(false)

  useEffect(() => { localStorage.setItem(STORAGE_KEY, JSON.stringify(tasks)) }, [tasks])
  useEffect(() => {
    const onKey = event => { if (event.key === 'Escape') { setDialogTask(null); setCreating(false); setFiltersOpen(false); setNotificationsOpen(false) } }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [])

  const visibleTasks = useMemo(() => tasks.filter(task => {
    const term = search.trim().toLowerCase()
    const matchesText = !term || `${task.title} ${task.description} ${task.labels.join(' ')}`.toLowerCase().includes(term)
    const matchesMember = !memberFilter || task.members.includes(memberFilter)
    const matchesLabel = !labelFilter || task.labels.includes(labelFilter)
    const due = dueLabel(task.due)
    const matchesDue = !dueFilter || (dueFilter === 'overdue' ? due?.state === 'overdue' : dueFilter === 'soon' ? due?.state === 'soon' : !task.due)
    return matchesText && matchesMember && matchesLabel && matchesDue
  }), [tasks, search, memberFilter, labelFilter, dueFilter])

  const notify = message => { setNotice(message); window.setTimeout(() => setNotice(''), 2600) }
  const saveTask = task => {
    setTasks(current => task.id ? current.map(item => item.id === task.id ? task : item) : [...current, { ...task, id: crypto.randomUUID() }])
    setDialogTask(null); setCreating(false); notify(task.id ? 'Changes saved' : 'Task added to your board')
  }
  const deleteTask = id => { setTasks(current => current.filter(task => task.id !== id)); setDialogTask(null); notify('Task deleted') }
  const addColumn = () => {
    const name = window.prompt('Name your new list')
    if (!name?.trim()) return
    const id = name.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-')
    if (!boardColumns.some(column => column.id === id)) {
      setBoardColumns(current => [...current, { id, name: name.trim(), tone: 'slate' }])
      notify(`${name.trim()} list added`)
    }
  }
  const activeFilters = [memberFilter, labelFilter, dueFilter].filter(Boolean).length

  return <div className="app-shell">
    <aside className={`sidebar ${mobileNavOpen ? 'sidebar-open' : ''}`}>
      <a className="brand" href="#board" aria-label="Orbit home"><span className="brand-mark"><Icon name="grid" size={19}/></span><span>orbit<span className="brand-dot">.</span></span></a>
      <button className="workspace-switcher" onClick={() => notify('Workspace switcher is ready for connected workspaces')}><span className="workspace-avatar">N</span><span className="workspace-copy"><strong>Northstar Studio</strong><small>Free workspace</small></span><Icon name="chevron" size={16}/></button>
      <nav aria-label="Main navigation"><p className="nav-label">WORKSPACE</p><a className="nav-item" href="#inbox" onClick={event => {event.preventDefault(); notify('Inbox view is coming next')}}><span className="nav-icon">✳</span>Inbox<span className="nav-count">3</span></a><a className="nav-item active" href="#board"><Icon name="board"/>Boards</a><a className="nav-item" href="#calendar" onClick={event => {event.preventDefault(); notify('Calendar view is coming next')}}><Icon name="calendar"/>Calendar</a><a className="nav-item" href="#members" onClick={event => {event.preventDefault(); notify('Workspace members are managed in settings')}}><span className="nav-icon">◎</span>Members</a>
        <div className="nav-section"><p className="nav-label">YOUR BOARDS <button aria-label="Add board" onClick={() => notify('Board creation is coming next')}>+</button></p><a className="board-link selected" href="#board"><span className="board-color lavender"/>Product launch</a><a className="board-link" href="#campaign" onClick={event => {event.preventDefault(); notify('This sample board is not connected yet')}}><span className="board-color peach"/>Q4 campaign</a><a className="board-link" href="#website" onClick={event => {event.preventDefault(); notify('This sample board is not connected yet')}}><span className="board-color mint"/>Website refresh</a><a className="board-link" href="#requirements" onClick={event => {event.preventDefault(); window.open('./reference-prototype.html', '_blank', 'noopener,noreferrer')}}><span className="board-color blue"/>Requirements map</a></div>
      </nav>
      <div className="sidebar-bottom"><a className="help-link" href="#help" onClick={event => {event.preventDefault(); notify('Help center will be connected later')}}>ⓘ <span>Help & shortcuts</span></a><button className="profile-button" onClick={() => notify('Account settings are not connected yet')}><Avatar person={people[0]}/><span><strong>Nicha K.</strong><small>Product designer</small></span><Icon name="dots"/></button></div>
    </aside>

    <main className="main-area" id="board">
      <header className="topbar"><button className="mobile-menu icon-button" onClick={() => setMobileNavOpen(value => !value)} aria-label="Toggle navigation"><Icon name="grid"/></button><div className="breadcrumbs"><span>Northstar Studio</span><span className="crumb-separator">/</span><strong>Product launch</strong></div><div className="top-actions"><label className="search-box"><Icon name="search" size={17}/><input value={search} onChange={event => setSearch(event.target.value)} placeholder="Search tasks…" aria-label="Search tasks"/><kbd>⌘ K</kbd></label><div className="notification-wrap"><button className={`icon-button notification-button ${notificationsOpen ? 'pressed' : ''}`} onClick={() => setNotificationsOpen(value => !value)} aria-label="Open notifications"><Icon name="bell"/><i/></button>{notificationsOpen && <div className="notification-popover"><div className="popover-heading"><strong>Notifications</strong><button onClick={() => notify('All caught up')}>Mark all read</button></div><div className="notification-row"><Avatar person={people[2]} small/><p><strong>May R.</strong> mentioned you in <b>Onboarding journey</b><small>12 minutes ago</small></p></div><div className="notification-row"><Avatar person={people[3]} small/><p><strong>Pimchanok</strong> moved <b>Dashboard empty states</b> to review<small>1 hour ago</small></p></div><div className="notification-row"><span className="notification-dot"/><p>Your task <b>Share weekly progress</b> is complete<small>Yesterday</small></p></div></div>}</div><Avatar person={people[0]}/></div></header>
      <section className="board-content">
        <div className="board-heading"><div><div className="board-overline"><span>PRODUCT</span><span>·</span><span>Q4 2026</span><button className="favorite-button" aria-label="Favorite board" onClick={event => event.currentTarget.classList.toggle('favorited')}>☆</button></div><div className="title-row"><h1>Product launch</h1><span className="visibility-pill"><span/>Private</span></div><p className="board-description">A calm place to bring our next big idea to life.</p></div><div className="board-heading-actions"><div className="board-members"><Avatars memberIds={people.map(person => person.id)}/><span>+2</span></div><button className="button secondary invite-button" onClick={() => notify('Invite link copied to clipboard')}>↗ <span>Share</span></button><button className="button primary" onClick={() => setCreating(true)}><Icon name="plus" size={17}/> Add task</button></div></div>
        <div className="board-toolbar"><div className="toolbar-left"><button className={`toolbar-button ${filtersOpen || activeFilters ? 'toolbar-active' : ''}`} onClick={() => setFiltersOpen(value => !value)}><Icon name="filter" size={16}/> Filters{activeFilters > 0 && <span className="filter-count">{activeFilters}</span>}</button>{(memberFilter || labelFilter || dueFilter) && <button className="clear-filters" onClick={() => {setMemberFilter('');setLabelFilter('');setDueFilter('')}}>Clear filters</button>}<span className="toolbar-divider"/><span className="view-caption">Showing <strong>{visibleTasks.length}</strong> tasks</span></div><div className="toolbar-right"><span className="view-caption">View</span><button className="view-toggle selected" aria-label="Board view"><Icon name="board" size={16}/></button><button className="view-toggle" aria-label="List view" onClick={() => notify('List view is coming next')}>☷</button><button className="icon-button subtle-icon" aria-label="More board actions" onClick={() => notify('Board settings are coming next')}><Icon name="dots"/></button></div>{filtersOpen && <div className="filter-popover"><div className="filter-popover-head"><strong>Filter tasks</strong><button className="icon-button small-icon" onClick={() => setFiltersOpen(false)} aria-label="Close filters"><Icon name="close" size={15}/></button></div><label>Assigned to<select value={memberFilter} onChange={event => setMemberFilter(event.target.value)}><option value="">Anyone</option>{people.map(person => <option key={person.id} value={person.id}>{person.name}</option>)}</select></label><label>Label<select value={labelFilter} onChange={event => setLabelFilter(event.target.value)}><option value="">All labels</option>{Object.keys(labelColors).map(label => <option key={label}>{label}</option>)}</select></label><label>Due date<select value={dueFilter} onChange={event => setDueFilter(event.target.value)}><option value="">Any time</option><option value="overdue">Overdue</option><option value="soon">Due soon</option><option value="none">No due date</option></select></label><button className="button primary apply-filter" onClick={() => setFiltersOpen(false)}>Show {visibleTasks.length} tasks</button></div>}</div>
        <div className="board-scroll"><div className="board-columns">{boardColumns.map(column => {
          const columnTasks = visibleTasks.filter(task => task.column === column.id)
          return <section className="board-column" key={column.id} aria-label={`${column.name}, ${columnTasks.length} tasks`}><header className="column-heading"><span className={`column-dot ${column.tone}`}/><h2>{column.name}</h2><span className="column-count">{columnTasks.length}</span><button className="column-menu" aria-label={`${column.name} options`} onClick={() => notify(`${column.name} list options`)}><Icon name="dots" size={17}/></button></header><div className="column-tasks">{columnTasks.map(task => <TaskCard task={task} key={task.id} onOpen={setDialogTask}/>)}{columnTasks.length === 0 && <p className="empty-column">No tasks match these filters.</p>}</div><button className="add-task-link" onClick={() => {setCreating(true)}}><Icon name="plus" size={16}/> Add a task</button></section>
        })}<button className="add-column" onClick={addColumn}><Icon name="plus" size={17}/> Add another list</button></div></div>
        <div className="board-footnote"><span className="sync-dot"/> Your board is up to date <span>·</span> Changes are saved in this browser</div>
      </section>
    </main>
    {(dialogTask || creating) && <TaskDialog key={dialogTask?.id || 'new'} task={dialogTask} columns={boardColumns} onClose={() => {setDialogTask(null);setCreating(false)}} onSave={saveTask} onDelete={deleteTask} canDelete/>}
    {notice && <div className="toast" role="status">{notice}</div>}
  </div>
}

export default App
