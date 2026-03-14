import { Link, usePage, router } from '@inertiajs/react';
import { useState } from 'react';


export default function Index({ employees }) {
    const { flash } = usePage().props;
    const [searchTerm, setSearchTerm] = useState('');


    // Real-time logic removed. To update employees, refresh manually or implement polling if needed.

    const filteredEmployees = employees.filter(emp =>
        emp.first_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        emp.last_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        emp.email.toLowerCase().includes(searchTerm.toLowerCase())
    );

    const handleDelete = (id) => {
        if (confirm('Are you sure you want to delete this employee?')) {
            router.delete(route('employees.destroy', id));
        }
    };

    return (
        <div style={{ padding: '30px', backgroundColor: '#f5f5f5', minHeight: '100vh' }}>
            <div style={{ maxWidth: '1200px', margin: '0 auto' }}>

                {/* Flash Message */}
                {flash?.success && (
                    <div style={{
                        background: '#d4edda',
                        color: '#155724',
                        padding: '15px',
                        marginBottom: '20px',
                        borderRadius: '4px',
                        border: '1px solid #c3e6cb'
                    }}>
                        ✓ {flash.success}
                    </div>
                )}

                {/* Header */}
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '30px' }}>
                    <h1 style={{ margin: 0, color: '#333' }}>Employees</h1>
                    <Link
                        href={route('employees.create')}
                        style={{
                            background: '#007bff',
                            color: 'white',
                            padding: '10px 20px',
                            borderRadius: '4px',
                            cursor: 'pointer',
                            fontSize: '14px',
                            fontWeight: 'bold',
                            textDecoration: 'none',
                            display: 'inline-block'
                        }}
                    >
                        + Add Employee
                    </Link>
                </div>

                {/* Search */}
                <div style={{ marginBottom: '20px' }}>
                    <input
                        type="text"
                        placeholder="Search by name or email..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        style={{
                            width: '100%',
                            padding: '10px',
                            borderRadius: '4px',
                            border: '1px solid #ddd',
                            fontSize: '14px'
                        }}
                    />
                </div>

                {/* Table */}
                <div style={{ overflowX: 'auto', background: 'white', borderRadius: '4px', boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
                    <table style={{ width: '100%', borderCollapse: 'collapse' }}>
                        <thead>
                            <tr style={{ background: '#f8f9fa', borderBottom: '2px solid #dee2e6' }}>
                                <th style={thStyle}>Photo</th>
                                <th style={thStyle}>Name</th>
                                <th style={thStyle}>Email</th>
                                <th style={thStyle}>Position</th>
                                <th style={thStyle}>Salary</th>
                                <th style={thStyle}>Hire Date</th>
                                <th style={thStyle}>Status</th>
                                <th style={thStyle}>CV</th>
                                <th style={{ ...thStyle, textAlign: 'center' }}>Actions</th>
                            </tr>
                        </thead>

                        <tbody>
                            {filteredEmployees.length ? (
                                filteredEmployees.map(employee => (
                                    <tr key={employee.id} style={{ borderBottom: '1px solid #dee2e6' }}>
                                        <td style={{ ...tdStyle, width: '60px' }}>
                                            {employee.profile_photo_url ? (
                                                <img
                                                    src={employee.profile_photo_url}
                                                    alt={`${employee.first_name} ${employee.last_name}`}
                                                    style={{ width: '40px', height: '40px', borderRadius: '50%', objectFit: 'cover', border: '2px solid #ddd' }}
                                                />
                                            ) : (
                                                <div style={{ width: '40px', height: '40px', borderRadius: '50%', background: '#007bff', color: 'white', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 'bold', fontSize: '14px' }}>
                                                    {employee.first_name[0]}{employee.last_name[0]}
                                                </div>
                                            )}
                                        </td>
                                        <td style={tdStyle}>
                                            {employee.first_name} {employee.last_name}
                                        </td>
                                        <td style={tdStyle}>{employee.email}</td>
                                        <td style={tdStyle}>{employee.position}</td>
                                        <td style={tdStyle}>${parseFloat(employee.salary).toFixed(2)}</td>
                                        <td style={tdStyle}>
                                            {new Date(employee.hire_date).toLocaleDateString()}
                                        </td>
                                        <td style={tdStyle}>
                                            <span style={{
                                                padding: '6px 12px',
                                                borderRadius: '20px',
                                                fontSize: '12px',
                                                fontWeight: 'bold',
                                                background: employee.status === 'active' ? '#d4edda' : '#f8d7da',
                                                color: employee.status === 'active' ? '#155724' : '#721c24'
                                            }}>
                                                {employee.status}
                                            </span>
                                        </td>
                                        <td style={tdStyle}>
                                            {employee.resume_url ? (
                                                <a
                                                    href={employee.resume_url}
                                                    target="_blank"
                                                    rel="noreferrer"
                                                    style={{ color: '#007bff', fontWeight: 'bold', fontSize: '13px', textDecoration: 'none', whiteSpace: 'nowrap' }}
                                                >
                                                    View CV
                                                </a>
                                            ) : (
                                                <span style={{ color: '#ccc', fontSize: '13px' }}>—</span>
                                            )}
                                        </td>
                                        <td style={{ ...tdStyle, textAlign: 'center' }}>
                                            <Link
                                                href={route('employees.edit', employee.id)}
                                                style={editBtnStyle}
                                            >
                                                Edit
                                            </Link>
                                            <button
                                                onClick={() => handleDelete(employee.id)}
                                                style={deleteBtnStyle}
                                            >
                                                Delete
                                            </button>
                                        </td>
                                    </tr>
                                ))
                            ) : (
                                <tr>
                                    <td colSpan="9" style={{ padding: '30px', textAlign: 'center', color: '#999' }}>
                                        No employees found
                                    </td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    );
}

/* ===== Styles ===== */
const thStyle = {
    padding: '15px',
    textAlign: 'left',
    fontWeight: 'bold',
    color: '#333'
};

const tdStyle = {
    padding: '15px',
    color: '#333'
};

const editBtnStyle = {
    background: '#28a745',
    color: 'white',
    padding: '6px 12px',
    borderRadius: '4px',
    cursor: 'pointer',
    marginRight: '5px',
    fontSize: '12px',
    fontWeight: 'bold',
    textDecoration: 'none',
    display: 'inline-block'
};

const deleteBtnStyle = {
    background: '#dc3545',
    color: 'white',
    padding: '6px 12px',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '12px',
    fontWeight: 'bold'
};
