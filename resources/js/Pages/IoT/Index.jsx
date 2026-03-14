import { useEffect, useRef, useState } from 'react';
import { Link } from '@inertiajs/react';

const EVENT_COLORS = {
    button_press: { bg: '#d4edda', color: '#155724', label: 'Button Press' },
    sensor_read:  { bg: '#cce5ff', color: '#004085', label: 'Sensor Read'  },
    heartbeat:    { bg: '#fff3cd', color: '#856404', label: 'Heartbeat'    },
    error:        { bg: '#f8d7da', color: '#721c24', label: 'Error'        },
};

function eventStyle(type) {
    return EVENT_COLORS[type] ?? { bg: '#e2e3e5', color: '#383d41', label: type };
}

function formatTime(ts) {
    if (!ts) return '—';
    const d = new Date(ts);
    return d.toLocaleString();
}

export default function IoTIndex() {
    const [events, setEvents] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [lastUpdated, setLastUpdated] = useState(null);
    const [live, setLive] = useState(true);
    const intervalRef = useRef(null);

    const fetchEvents = async () => {
        try {
            const res = await fetch('/iot-events', {
                headers: {
                    'Accept': 'application/json',
                    'X-Requested-With': 'XMLHttpRequest',
                },
            });
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const data = await res.json();
            setEvents(data);
            setLastUpdated(new Date());
            setError(null);
        } catch (e) {
            setError('Failed to fetch events: ' + e.message);
        } finally {
            setLoading(false);
        }
    };

    useEffect(() => {
        fetchEvents();
    }, []);

    useEffect(() => {
        if (live) {
            intervalRef.current = setInterval(fetchEvents, 3000);
        } else {
            clearInterval(intervalRef.current);
        }
        return () => clearInterval(intervalRef.current);
    }, [live]);

    return (
        <div style={{ padding: '30px', backgroundColor: '#f5f5f5', minHeight: '100vh' }}>
            <div style={{ maxWidth: '1200px', margin: '0 auto' }}>

                {/* Nav */}
                <div style={{ marginBottom: '20px' }}>
                    <Link
                        href="/employees"
                        style={{ color: '#007bff', textDecoration: 'none', fontSize: '14px' }}
                    >
                        ← Employees
                    </Link>
                </div>

                {/* Header */}
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
                    <div>
                        <h1 style={{ margin: 0, color: '#333' }}>IoT Live Data</h1>
                        <p style={{ margin: '4px 0 0', color: '#666', fontSize: '13px' }}>
                            M5Stack Core 2 events via Kinesis → Lambda → PostgreSQL
                        </p>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                        {lastUpdated && (
                            <span style={{ fontSize: '12px', color: '#888' }}>
                                Updated: {lastUpdated.toLocaleTimeString()}
                            </span>
                        )}
                        <button
                            onClick={() => setLive(l => !l)}
                            style={{
                                padding: '8px 16px',
                                borderRadius: '4px',
                                border: 'none',
                                cursor: 'pointer',
                                fontWeight: 'bold',
                                fontSize: '13px',
                                background: live ? '#28a745' : '#6c757d',
                                color: 'white',
                            }}
                        >
                            {live ? '● Live' : '○ Paused'}
                        </button>
                        <button
                            onClick={fetchEvents}
                            style={{
                                padding: '8px 16px',
                                borderRadius: '4px',
                                border: '1px solid #ddd',
                                cursor: 'pointer',
                                fontSize: '13px',
                                background: 'white',
                                color: '#333',
                            }}
                        >
                            Refresh
                        </button>
                    </div>
                </div>

                {/* Error */}
                {error && (
                    <div style={{ background: '#f8d7da', color: '#721c24', padding: '12px', borderRadius: '4px', marginBottom: '16px', border: '1px solid #f5c6cb' }}>
                        {error}
                    </div>
                )}

                {/* Stats Bar */}
                {!loading && (
                    <div style={{ display: 'flex', gap: '12px', marginBottom: '20px', flexWrap: 'wrap' }}>
                        <StatCard label="Total Events" value={events.length} color="#007bff" />
                        <StatCard
                            label="Button Presses"
                            value={events.filter(e => e.event_type === 'button_press').length}
                            color="#28a745"
                        />
                        <StatCard
                            label="Devices"
                            value={new Set(events.map(e => e.device_id)).size}
                            color="#6f42c1"
                        />
                        {events[0]?.battery_pct != null && (
                            <StatCard
                                label="Last Battery"
                                value={`${parseFloat(events[0].battery_pct).toFixed(1)}%`}
                                color="#fd7e14"
                            />
                        )}
                    </div>
                )}

                {/* Table */}
                <div style={{ overflowX: 'auto', background: 'white', borderRadius: '4px', boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
                    {loading ? (
                        <div style={{ padding: '40px', textAlign: 'center', color: '#666' }}>
                            Loading events...
                        </div>
                    ) : events.length === 0 ? (
                        <div style={{ padding: '40px', textAlign: 'center', color: '#999' }}>
                            No IoT events yet. Press a button on the M5Stack device.
                        </div>
                    ) : (
                        <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                            <thead>
                                <tr style={{ background: '#f8f9fa', borderBottom: '2px solid #dee2e6' }}>
                                    <th style={thStyle}>Time</th>
                                    <th style={thStyle}>Device</th>
                                    <th style={thStyle}>Event</th>
                                    <th style={thStyle}>Button</th>
                                    <th style={thStyle}>Message</th>
                                    <th style={thStyle}>Battery</th>
                                    <th style={thStyle}>Metadata</th>
                                </tr>
                            </thead>
                            <tbody>
                                {events.map(ev => {
                                    const style = eventStyle(ev.event_type);
                                    return (
                                        <tr key={ev.id} style={{ borderBottom: '1px solid #dee2e6' }}>
                                            <td style={{ ...tdStyle, whiteSpace: 'nowrap', fontSize: '12px' }}>
                                                {formatTime(ev.created_at)}
                                            </td>
                                            <td style={{ ...tdStyle, fontFamily: 'monospace', fontSize: '12px' }}>
                                                {ev.device_id}
                                            </td>
                                            <td style={tdStyle}>
                                                <span style={{
                                                    padding: '4px 10px',
                                                    borderRadius: '20px',
                                                    fontSize: '11px',
                                                    fontWeight: 'bold',
                                                    background: style.bg,
                                                    color: style.color,
                                                    whiteSpace: 'nowrap',
                                                }}>
                                                    {style.label}
                                                </span>
                                            </td>
                                            <td style={{ ...tdStyle, textAlign: 'center', fontWeight: 'bold' }}>
                                                {ev.button ?? <span style={{ color: '#ccc' }}>—</span>}
                                            </td>
                                            <td style={{ ...tdStyle, maxWidth: '240px' }}>
                                                {ev.message ?? <span style={{ color: '#ccc' }}>—</span>}
                                            </td>
                                            <td style={tdStyle}>
                                                {ev.battery_pct != null ? (
                                                    <span style={{ color: ev.battery_pct < 20 ? '#dc3545' : '#333' }}>
                                                        {parseFloat(ev.battery_pct).toFixed(1)}%
                                                    </span>
                                                ) : (
                                                    <span style={{ color: '#ccc' }}>—</span>
                                                )}
                                            </td>
                                            <td style={{ ...tdStyle, fontSize: '11px', fontFamily: 'monospace', color: '#666', maxWidth: '180px', wordBreak: 'break-all' }}>
                                                {ev.metadata && Object.keys(ev.metadata).length > 0
                                                    ? JSON.stringify(ev.metadata)
                                                    : <span style={{ color: '#ccc' }}>—</span>}
                                            </td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                    )}
                </div>

                <p style={{ marginTop: '12px', fontSize: '12px', color: '#aaa', textAlign: 'right' }}>
                    {live ? 'Polling every 3 s' : 'Polling paused'} · Showing last 50 events
                </p>
            </div>
        </div>
    );
}

function StatCard({ label, value, color }) {
    return (
        <div style={{
            background: 'white',
            borderRadius: '4px',
            padding: '12px 20px',
            boxShadow: '0 1px 3px rgba(0,0,0,0.1)',
            borderLeft: `4px solid ${color}`,
            minWidth: '120px',
        }}>
            <div style={{ fontSize: '22px', fontWeight: 'bold', color }}>{value}</div>
            <div style={{ fontSize: '12px', color: '#666', marginTop: '2px' }}>{label}</div>
        </div>
    );
}

const thStyle = {
    padding: '12px 15px',
    textAlign: 'left',
    fontWeight: 'bold',
    color: '#333',
    fontSize: '13px',
};

const tdStyle = {
    padding: '12px 15px',
    color: '#333',
    fontSize: '13px',
};
