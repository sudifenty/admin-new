import { useEffect, useMemo, useRef, useState } from 'react';

const GLOBAL_LIMIT_KEY = 'global_daily_limit';
const STUDENTS_KEY = 'smartple_students';
const CLASS_LIMITS_KEY = 'class_daily_limits';
const DEFAULT_LIMIT = 20;
const PRESET_LIMITS = [0, 5, 10, 20, 50];
const CLASS_NAMES = ['P5', 'P6', 'P7'];

const MOCK_STUDENTS = [
  { id: 'st-001', name: 'Aaliyah Namusoke', className: 'P7', limitOverride: null },
  { id: 'st-002', name: 'Daniel Okello', className: 'P6', limitOverride: null },
  { id: 'st-003', name: 'Grace Achieng', className: 'P5', limitOverride: null },
  { id: 'st-004', name: 'Isaac Mugisha', className: 'P7', limitOverride: null },
  { id: 'st-005', name: 'Miriam Nansubuga', className: 'P6', limitOverride: null },
  { id: 'st-006', name: 'Peter Kato', className: 'P5', limitOverride: null },
  { id: 'st-007', name: 'Sarah Atim', className: 'P7', limitOverride: null },
  { id: 'st-008', name: 'David Ssemanda', className: 'P6', limitOverride: null },
  { id: 'st-009', name: 'Ruth Nakato', className: 'P5', limitOverride: null },
  { id: 'st-010', name: 'Brian Ouma', className: 'P7', limitOverride: null },
];

function safeGet(key) {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function safeSet(key, value) {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // The dashboard still works for this session if storage is unavailable.
  }
}

function safeGetJson(key) {
  const raw = safeGet(key);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function isValidLimit(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function readGlobalLimit() {
  const raw = safeGet(GLOBAL_LIMIT_KEY);
  if (raw === null || raw.trim() === '') return DEFAULT_LIMIT;
  const parsed = Number(raw);
  return isValidLimit(parsed) ? parsed : DEFAULT_LIMIT;
}

function readStudents() {
  const stored = safeGetJson(STUDENTS_KEY);
  if (!Array.isArray(stored)) return MOCK_STUDENTS;
  return MOCK_STUDENTS.map((mockStudent) => {
    const savedStudent = stored.find((student) => student?.id === mockStudent.id);
    const savedLimit = savedStudent?.limitOverride;
    return {
      ...mockStudent,
      limitOverride: savedLimit === null || isValidLimit(savedLimit) ? (savedLimit ?? null) : null,
    };
  });
}

function readClassLimits() {
  const stored = safeGetJson(CLASS_LIMITS_KEY);
  return Object.fromEntries(
    CLASS_NAMES.map((className) => {
      const value = stored?.[className];
      return [className, value === null || isValidLimit(value) ? (value ?? null) : null];
    }),
  );
}

function choiceFromLimit(value) {
  if (value === null || value === undefined) return '';
  return PRESET_LIMITS.includes(value) ? String(value) : 'custom';
}

function customValueFromLimit(value) {
  return value !== null && value !== undefined && !PRESET_LIMITS.includes(value) ? String(value) : '';
}

function initialClassDrafts() {
  const saved = readClassLimits();
  return Object.fromEntries(
    CLASS_NAMES.map((className) => [
      className,
      {
        choice: choiceFromLimit(saved[className]),
        custom: customValueFromLimit(saved[className]),
        dirty: false,
      },
    ]),
  );
}

function limitLabel(value) {
  return value === 0 ? '0 questions/day' : `${value} ${questionWord(value)}/day`;
}

function questionWord(value) {
  return value === 1 ? 'question' : 'questions';
}

function limitDescription(value) {
  return value === 0 ? 'Paused · no questions' : `${value} ${questionWord(value)} per day`;
}

function initials(name) {
  return name
    .split(' ')
    .map((part) => part[0])
    .slice(0, 2)
    .join('')
    .toUpperCase();
}

function Icon({ name, size = 20, strokeWidth = 1.8, className = '' }) {
  const common = {
    width: size,
    height: size,
    viewBox: '0 0 24 24',
    fill: 'none',
    stroke: 'currentColor',
    strokeWidth,
    strokeLinecap: 'round',
    strokeLinejoin: 'round',
    className,
    'aria-hidden': true,
  };

  const shapes = {
    people: <><path d="M16 21v-2a4 4 0 0 0-4-4H7a4 4 0 0 0-4 4v2" /><circle cx="9.5" cy="7" r="4" /><path d="M20 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75" /></>,
    gauge: <><path d="M4.93 19a9 9 0 1 1 14.14 0" /><path d="m12 13 4-4" /><path d="M12 21v-2" /><path d="M4 17H2m20 0h-2" /></>,
    search: <><circle cx="11" cy="11" r="7" /><path d="m20 20-4-4" /></>,
    check: <path d="m5 12 4 4L19 6" />,
    globe: <><circle cx="12" cy="12" r="9" /><path d="M3.6 9h16.8M3.6 15h16.8" /><path d="M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18" /></>,
    chevron: <path d="m7 10 5 5 5-5" />,
    close: <><path d="m18 6-12 12M6 6l12 12" /></>,
    arrow: <><path d="M7 17 17 7M7 7h10v10" /></>,
    pause: <><path d="M8 5v14M16 5v14" /></>,
    sparkle: <><path d="m12 3 1.5 5.5L19 10l-5.5 1.5L12 17l-1.5-5.5L5 10l5.5-1.5L12 3Z" /><path d="m19 16 .7 2.3L22 19l-2.3.7L19 22l-.7-2.3L16 19l2.3-.7L19 16Z" /></>,
  };

  return <svg {...common}>{shapes[name] || null}</svg>;
}

function BrandMark() {
  return (
    <span className="brand-mark" aria-hidden="true">
      <svg viewBox="0 0 40 40" width="30" height="30" fill="none">
        <path d="M8 27.5V16.2c0-1.2.7-2.2 1.8-2.7L19 9.2c.6-.3 1.4-.3 2 0l9.2 4.3c1.1.5 1.8 1.6 1.8 2.7v11.3" stroke="white" strokeWidth="2.3" strokeLinecap="round" />
        <path d="M13 27V18l7-3.5 7 3.5v9" stroke="white" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round" />
        <path d="M17 27v-5h6v5" stroke="white" strokeWidth="2.3" strokeLinecap="round" strokeLinejoin="round" />
        <circle cx="20" cy="11" r="1.4" fill="#BBD6FF" />
      </svg>
    </span>
  );
}

function LimitOption({ value, selected, onClick, compact = false }) {
  const custom = value === 'custom';
  const subtitles = {
    0: 'Paused',
    5: 'questions',
    10: 'questions',
    20: 'questions',
    50: 'questions',
    custom: 'Set amount',
  };
  const title = custom ? 'Custom' : String(value);

  return (
    <button
      type="button"
      className={`limit-option${compact ? ' compact' : ''}${selected ? ' selected' : ''}${custom ? ' custom-option' : ''}`}
      aria-pressed={selected}
      onClick={onClick}
    >
      {custom ? (
        <span className="custom-option-icon"><Icon name="sparkle" size={compact ? 15 : 17} /></span>
      ) : (
        <span className="option-number">{title}</span>
      )}
      <span className="option-caption">{subtitles[value]}</span>
    </button>
  );
}

function CustomLimitInput({ value, onChange, id, onSubmit, compact = false }) {
  const hasValue = value.trim() !== '';
  const numeric = Number(value);
  const valid = hasValue && isValidLimit(numeric);

  return (
    <div className={`custom-limit-field${compact ? ' compact-field' : ''}`}>
      <label htmlFor={id}>Custom daily limit</label>
      <div className="number-input-wrap">
        <input
          id={id}
          type="number"
          inputMode="numeric"
          min="0"
          step="1"
          value={value}
          onChange={(event) => onChange(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === 'Enter' && valid) onSubmit?.();
          }}
          placeholder="e.g. 30"
          aria-invalid={hasValue && !valid}
        />
        <span>questions / day</span>
      </div>
      <span className={`input-hint${hasValue && !valid ? ' input-error' : ''}`}>
        {hasValue && !valid ? 'Enter a whole number of 0 or more.' : 'Use any whole number, including 0.'}
      </span>
    </div>
  );
}

function StatCard({ icon, label, value, unit, note, tint = 'blue' }) {
  return (
    <article className="stat-card">
      <div className={`stat-icon-tile ${tint}`}><Icon name={icon} size={22} /></div>
      <div className="stat-copy">
        <div className="stat-label">{label}</div>
        <div className="stat-number-line">
          <strong>{value}</strong>
          {unit && <span>{unit}</span>}
        </div>
        <div className="stat-note">{note}</div>
      </div>
      <span className="stat-corner-mark"><Icon name="arrow" size={15} /></span>
    </article>
  );
}

function App() {
  const [globalLimit, setGlobalLimit] = useState(readGlobalLimit);
  const [globalChoice, setGlobalChoice] = useState(() => choiceFromLimit(readGlobalLimit()));
  const [globalCustom, setGlobalCustom] = useState(() => customValueFromLimit(readGlobalLimit()));
  const [students, setStudents] = useState(readStudents);
  const [classLimits, setClassLimits] = useState(readClassLimits);
  const [classDrafts, setClassDrafts] = useState(initialClassDrafts);
  const [studentEdits, setStudentEdits] = useState({});
  const [expandedStudentId, setExpandedStudentId] = useState(null);
  const [search, setSearch] = useState('');
  const [toast, setToast] = useState(null);
  const toastTimer = useRef(null);

  useEffect(() => {
    safeSet(GLOBAL_LIMIT_KEY, String(globalLimit));
  }, [globalLimit]);

  useEffect(() => {
    safeSet(STUDENTS_KEY, JSON.stringify(students));
  }, [students]);

  useEffect(() => {
    safeSet(CLASS_LIMITS_KEY, JSON.stringify(classLimits));
  }, [classLimits]);

  useEffect(() => () => window.clearTimeout(toastTimer.current), []);

  const notify = (message) => {
    window.clearTimeout(toastTimer.current);
    setToast({ message, id: Date.now() });
    toastTimer.current = window.setTimeout(() => setToast(null), 3600);
  };

  const visibleStudents = useMemo(() => {
    const normalizedSearch = search.trim().toLowerCase();
    if (!normalizedSearch) return students;
    return students.filter((student) =>
      `${student.name} ${student.className}`.toLowerCase().includes(normalizedSearch),
    );
  }, [students, search]);

  const classCounts = useMemo(
    () => Object.fromEntries(CLASS_NAMES.map((className) => [
      className,
      students.filter((student) => student.className === className).length,
    ])),
    [students],
  );

  const getEffectiveLimit = (student) => {
    if (student.limitOverride !== null) {
      return { value: student.limitOverride, source: 'Student override', type: 'individual' };
    }
    if (classLimits[student.className] !== null) {
      return { value: classLimits[student.className], source: `${student.className} class rule`, type: 'class' };
    }
    return { value: globalLimit, source: 'Global default', type: 'global' };
  };

  const saveGlobalLimit = () => {
    const value = globalChoice === 'custom' ? Number(globalCustom) : Number(globalChoice);
    if (!isValidLimit(value)) return;
    safeSet(GLOBAL_LIMIT_KEY, String(value));
    setGlobalLimit(value);
    notify(`All students will now get ${value} ${questionWord(value)} daily.`);
  };

  const setClassChoice = (className, choice) => {
    setClassDrafts((current) => {
      const existing = current[className] || { choice: '', custom: '', dirty: false };
      const persistedCustom = customValueFromLimit(classLimits[className]);
      return {
        ...current,
        [className]: {
          ...existing,
          choice,
          custom: choice === 'custom' ? (existing.custom || persistedCustom) : existing.custom,
          dirty: true,
        },
      };
    });
  };

  const setClassCustom = (className, value) => {
    setClassDrafts((current) => ({
      ...current,
      [className]: { ...current[className], custom: value, dirty: true },
    }));
  };

  const saveClassLimit = (className) => {
    const draft = classDrafts[className];
    const value = draft?.choice === 'custom' ? Number(draft.custom) : Number(draft?.choice);
    if (!draft?.dirty || !draft.choice || !isValidLimit(value)) return;
    const nextLimits = { ...classLimits, [className]: value };
    safeSet(CLASS_LIMITS_KEY, JSON.stringify(nextLimits));
    setClassLimits(nextLimits);
    setClassDrafts((current) => ({
      ...current,
      [className]: { choice: choiceFromLimit(value), custom: customValueFromLimit(value), dirty: false },
    }));
    notify(`${className} students will now get ${value} ${questionWord(value)} daily. Individual overrides stay in place.`);
  };

  const clearClassLimit = (className) => {
    const nextLimits = { ...classLimits, [className]: null };
    safeSet(CLASS_LIMITS_KEY, JSON.stringify(nextLimits));
    setClassLimits(nextLimits);
    setClassDrafts((current) => ({
      ...current,
      [className]: { choice: '', custom: '', dirty: false },
    }));
    notify(`${className} now follows the global default of ${limitLabel(globalLimit)}.`);
  };

  const toggleStudentEditor = (student) => {
    if (expandedStudentId === student.id) {
      setExpandedStudentId(null);
      return;
    }
    setExpandedStudentId(student.id);
    setStudentEdits((current) => {
      if (current[student.id]) return current;
      return {
        ...current,
        [student.id]: {
          choice: choiceFromLimit(student.limitOverride),
          custom: customValueFromLimit(student.limitOverride),
          dirty: false,
        },
      };
    });
  };

  const setStudentChoice = (student, choice) => {
    setStudentEdits((current) => {
      const existing = current[student.id] || {
        choice: choiceFromLimit(student.limitOverride),
        custom: customValueFromLimit(student.limitOverride),
        dirty: false,
      };
      return {
        ...current,
        [student.id]: {
          ...existing,
          choice,
          custom: choice === 'custom'
            ? (existing.custom || customValueFromLimit(student.limitOverride))
            : existing.custom,
          dirty: true,
        },
      };
    });
  };

  const setStudentCustom = (student, value) => {
    setStudentEdits((current) => ({
      ...current,
      [student.id]: { ...current[student.id], custom: value, dirty: true },
    }));
  };

  const saveStudentLimit = (student) => {
    const draft = studentEdits[student.id];
    const value = draft?.choice === 'custom' ? Number(draft.custom) : Number(draft?.choice);
    if (!draft?.dirty || !draft.choice || !isValidLimit(value)) return;
    const updatedStudents = students.map((item) =>
      item.id === student.id ? { ...item, limitOverride: value } : item,
    );
    safeSet(STUDENTS_KEY, JSON.stringify(updatedStudents));
    setStudents(updatedStudents);
    setStudentEdits((current) => ({ ...current, [student.id]: {
      choice: choiceFromLimit(value), custom: customValueFromLimit(value), dirty: false,
    } }));
    setExpandedStudentId(null);
    notify(`${student.name} will now get ${value} ${questionWord(value)} daily.`);
  };

  const clearStudentLimit = (student) => {
    const updatedStudents = students.map((item) =>
      item.id === student.id ? { ...item, limitOverride: null } : item,
    );
    safeSet(STUDENTS_KEY, JSON.stringify(updatedStudents));
    setStudents(updatedStudents);
    setExpandedStudentId(null);
    setStudentEdits((current) => {
      const next = { ...current };
      delete next[student.id];
      return next;
    });
    const inheritedSource = classLimits[student.className] !== null
      ? `${student.className} class limit (${limitLabel(classLimits[student.className])})`
      : `global default (${limitLabel(globalLimit)})`;
    notify(`${student.name} now follows the ${inheritedSource}.`);
  };

  const globalCustomNumber = Number(globalCustom);
  const globalCustomValid = globalCustom.trim() !== '' && isValidLimit(globalCustomNumber);
  const globalSelectedValue = globalChoice === 'custom' ? globalCustomNumber : Number(globalChoice);
  const globalCanSave = globalChoice !== '' && isValidLimit(globalSelectedValue);

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="topbar-inner mx-auto flex items-center justify-between">
          <div className="brand-lockup">
            <BrandMark />
            <span className="brand-name">SmartPle Admin</span>
            <span className="brand-divider" aria-hidden="true">—</span>
            <span className="brand-page">Remote Control</span>
          </div>
          <div className="topbar-status">
            <span className="phase-tag">PHASE 1 <span>·</span> UI ONLY</span>
            <span className="local-status"><i /> Local demo</span>
          </div>
        </div>
      </header>

      <main className="page-container mx-auto">
        <section className="page-intro">
          <div className="eyebrow"><span className="eyebrow-line" />ADMIN CONTROL CENTER</div>
          <h1>Daily question limits</h1>
          <p>Choose how many practice questions students can answer each day.</p>
        </section>

        <section className="stats-grid" aria-label="Dashboard overview">
          <StatCard
            icon="people"
            label="Total students"
            value="124"
            note="Mock school roster · 10 sample students below"
            tint="blue"
          />
          <StatCard
            icon="gauge"
            label="Current default"
            value={globalLimit}
            unit="questions / day"
            note="Global fallback · updates when you save"
            tint="mint"
          />
        </section>

        <section className="panel global-panel" aria-labelledby="global-heading">
          <div className="section-heading global-heading-row">
            <div>
              <div className="section-kicker"><span className="section-index">01</span> GLOBAL CONTROL</div>
              <h2 id="global-heading">Set for ALL Students</h2>
              <p>Set the daily question limit for everyone, unless a class or student has its own rule.</p>
            </div>
            <div className="active-limit-card">
              <span className="active-limit-icon"><Icon name="globe" size={19} /></span>
              <span className="active-limit-copy"><small>ACTIVE GLOBAL LIMIT</small><strong>{limitLabel(globalLimit)}</strong></span>
              <span className="active-check"><Icon name="check" size={15} /></span>
            </div>
          </div>

          <div className="option-prompt">Choose a new limit</div>
          <div className="global-options" role="group" aria-label="Global daily question limit">
            {PRESET_LIMITS.map((value) => (
              <LimitOption
                key={value}
                value={value}
                selected={globalChoice === String(value)}
                onClick={() => setGlobalChoice(String(value))}
              />
            ))}
            <LimitOption
              value="custom"
              selected={globalChoice === 'custom'}
              onClick={() => setGlobalChoice('custom')}
            />
          </div>

          {globalChoice === 'custom' && (
            <div className="global-custom-row">
              <CustomLimitInput
                id="global-custom-limit"
                value={globalCustom}
                onChange={setGlobalCustom}
                onSubmit={saveGlobalLimit}
              />
            </div>
          )}

          <div className="global-save-row">
            <div className="inherit-note"><span className="note-dot" /> Individual student rules take priority, then class rules, then this global default.</div>
            <button className="primary-button" type="button" onClick={saveGlobalLimit} disabled={!globalCanSave}>
              <Icon name="check" size={18} /> Save for all students
            </button>
          </div>
        </section>

        <section className="control-section" aria-labelledby="class-heading">
          <div className="section-title-row">
            <div>
              <div className="section-kicker"><span className="section-index">02</span> CLASS CONTROL</div>
              <h2 id="class-heading">Set a limit by class</h2>
              <p>Class rules override the global default. A student's personal rule always takes priority.</p>
            </div>
            <span className="section-meta"><span className="meta-dot" /> 3 classes</span>
          </div>

          <div className="class-grid">
            {CLASS_NAMES.map((className) => {
              const draft = classDrafts[className] || { choice: '', custom: '', dirty: false };
              const currentClassLimit = classLimits[className];
              const selectedChoice = draft.dirty ? draft.choice : choiceFromLimit(currentClassLimit);
              const currentCustom = draft.dirty ? draft.custom : customValueFromLimit(currentClassLimit);
              const customSelected = selectedChoice === 'custom';
              const customNumber = Number(currentCustom);
              const customValid = currentCustom.trim() !== '' && isValidLimit(customNumber);
              const selectedNumber = selectedChoice === 'custom' ? customNumber : Number(selectedChoice);
              const canSaveClass = draft.dirty && selectedChoice !== '' && isValidLimit(selectedNumber);

              return (
                <article className="class-card" key={className}>
                  <div className="class-card-top">
                    <div className="class-name-wrap">
                      <span className="class-badge">{className}</span>
                      <span className="class-student-count">{classCounts[className]} sample students</span>
                    </div>
                    {currentClassLimit !== null && <span className="rule-active-badge"><i /> Rule active</span>}
                  </div>

                  <div className="class-current-rule">
                    <span className="class-current-label">CURRENT CLASS LIMIT</span>
                    <strong>
                      {currentClassLimit === null
                        ? `Using global · ${limitLabel(globalLimit)}`
                        : limitLabel(currentClassLimit)}
                    </strong>
                  </div>

                  <div className="class-option-grid" role="group" aria-label={`Set ${className} daily question limit`}>
                    {PRESET_LIMITS.map((value) => (
                      <LimitOption
                        compact
                        key={value}
                        value={value}
                        selected={selectedChoice === String(value)}
                        onClick={() => setClassChoice(className, String(value))}
                      />
                    ))}
                    <LimitOption
                      compact
                      value="custom"
                      selected={customSelected}
                      onClick={() => setClassChoice(className, 'custom')}
                    />
                  </div>

                  {customSelected && (
                    <CustomLimitInput
                      compact
                      id={`${className.toLowerCase()}-custom-limit`}
                      value={currentCustom}
                      onChange={(value) => setClassCustom(className, value)}
                      onSubmit={() => saveClassLimit(className)}
                    />
                  )}

                  {canSaveClass && (
                    <button className="class-save-button" type="button" onClick={() => saveClassLimit(className)}>
                      Save {className} limit <Icon name="check" size={16} />
                    </button>
                  )}
                  {draft.dirty && customSelected && !customValid && currentCustom.trim() !== '' && (
                    <span className="class-validation">Enter a whole number of 0 or more.</span>
                  )}
                  {currentClassLimit !== null && !draft.dirty && (
                    <button className="clear-rule-button" type="button" onClick={() => clearClassLimit(className)}>
                      Remove class rule
                    </button>
                  )}
                  <div className="class-card-footnote">Personal student limits are not changed.</div>
                </article>
              );
            })}
          </div>
        </section>

        <section className="panel students-panel" aria-labelledby="students-heading">
          <div className="students-panel-header">
            <div className="section-title-row students-title-row">
              <div>
                <div className="section-kicker"><span className="section-index">03</span> STUDENT CONTROL</div>
                <h2 id="students-heading">Individual students</h2>
                <p>Set a personal limit for one student. It overrides their class and global settings.</p>
              </div>
              <span className="student-count-pill">10 demo students</span>
            </div>
            <label className="search-box">
              <Icon name="search" size={19} />
              <input
                type="search"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search by name or class..."
                aria-label="Search students by name or class"
              />
              {search && (
                <button type="button" className="clear-search" onClick={() => setSearch('')} aria-label="Clear search">
                  <Icon name="close" size={15} />
                </button>
              )}
            </label>
          </div>

          <div className="student-list" role="list">
            <div className="student-list-head" aria-hidden="true">
              <span>STUDENT</span><span>CLASS</span><span>CURRENT LIMIT</span><span>ACTION</span>
            </div>
            {visibleStudents.length > 0 ? visibleStudents.map((student, index) => {
              const effective = getEffectiveLimit(student);
              const expanded = expandedStudentId === student.id;
              const draft = studentEdits[student.id] || {
                choice: choiceFromLimit(student.limitOverride),
                custom: customValueFromLimit(student.limitOverride),
                dirty: false,
              };
              const customSelected = draft.choice === 'custom';
              const customNumber = Number(draft.custom);
              const customValid = draft.custom.trim() !== '' && isValidLimit(customNumber);
              const selectedNumber = customSelected ? customNumber : Number(draft.choice);
              const canSaveStudent = draft.dirty && draft.choice !== '' && isValidLimit(selectedNumber);

              return (
                <div className={`student-row-wrap${expanded ? ' row-expanded' : ''}`} role="listitem" key={student.id}>
                  <div className="student-row-main">
                    <div className="student-identity">
                      <span className={`student-avatar avatar-${index % 5}`}>{initials(student.name)}</span>
                      <span className="student-name-block">
                        <strong>{student.name}</strong>
                        <span className="student-class-mobile">{student.className}</span>
                      </span>
                    </div>
                    <div className="student-class-desktop"><span className="table-class-tag">{student.className}</span></div>
                    <div className="student-current-limit">
                      <span className={`effective-limit ${effective.type === 'individual' ? 'individual-limit' : ''}`}>
                        <strong>{limitLabel(effective.value)}</strong>
                      </span>
                      <span className={`limit-source source-${effective.type}`}>{effective.source}</span>
                    </div>
                    <button
                      type="button"
                      className={`student-change-button${expanded ? ' is-open' : ''}`}
                      onClick={() => toggleStudentEditor(student)}
                      aria-expanded={expanded}
                      aria-label={`${expanded ? 'Close' : 'Change'} daily limit for ${student.name}`}
                    >
                      {expanded ? 'Close' : 'Change limit'}
                      <Icon name="chevron" size={16} />
                    </button>
                  </div>

                  {expanded && (
                    <div className="student-editor">
                      <div className="student-editor-heading">
                        <div>
                          <strong>Set a limit for {student.name}</strong>
                          <span>This personal rule will override the {student.className} class rule and global default.</span>
                        </div>
                        {student.limitOverride !== null && <span className="personal-rule-tag"><i /> Personal rule active</span>}
                      </div>
                      <div className="student-option-grid" role="group" aria-label={`Set daily question limit for ${student.name}`}>
                        {PRESET_LIMITS.map((value) => (
                          <LimitOption
                            compact
                            key={value}
                            value={value}
                            selected={draft.choice === String(value)}
                            onClick={() => setStudentChoice(student, String(value))}
                          />
                        ))}
                        <LimitOption
                          compact
                          value="custom"
                          selected={customSelected}
                          onClick={() => setStudentChoice(student, 'custom')}
                        />
                      </div>
                      {customSelected && (
                        <CustomLimitInput
                          compact
                          id={`${student.id}-custom-limit`}
                          value={draft.custom}
                          onChange={(value) => setStudentCustom(student, value)}
                          onSubmit={() => saveStudentLimit(student)}
                        />
                      )}
                      <div className="student-editor-actions">
                        {student.limitOverride !== null ? (
                          <button type="button" className="text-action" onClick={() => clearStudentLimit(student)}>
                            Use class / global default instead
                          </button>
                        ) : <span className="editor-spacer" />}
                        {draft.dirty && customSelected && !customValid && draft.custom.trim() !== '' && (
                          <span className="student-validation">Enter a whole number of 0 or more.</span>
                        )}
                        {canSaveStudent && (
                          <button type="button" className="primary-button compact-primary" onClick={() => saveStudentLimit(student)}>
                            <Icon name="check" size={17} /> Save student limit
                          </button>
                        )}
                      </div>
                    </div>
                  )}
                </div>
              );
            }) : (
              <div className="empty-state">
                <span className="empty-icon"><Icon name="search" size={22} /></span>
                <strong>No students found</strong>
                <span>Try a different name or class.</span>
                <button type="button" onClick={() => setSearch('')}>Clear search</button>
              </div>
            )}
          </div>
          <div className="student-list-footnote">
            Showing {visibleStudents.length} of {students.length} sample students
            <span>·</span>
            Individual rules always take priority
          </div>
        </section>

        <footer className="page-footer">
          <span className="footer-lock"><span className="footer-dot" /> Changes save to this browser only.</span>
          <span>No connection to the student app or backend.</span>
        </footer>
      </main>

      {toast && (
        <div className="toast" role="status" aria-live="polite" key={toast.id}>
          <span className="toast-check"><Icon name="check" size={17} /></span>
          <span>{toast.message}</span>
          <button type="button" onClick={() => setToast(null)} aria-label="Dismiss notification"><Icon name="close" size={16} /></button>
        </div>
      )}
    </div>
  );
}

export default App;
