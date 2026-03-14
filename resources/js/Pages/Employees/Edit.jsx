import { useForm, Link } from '@inertiajs/react';
import { useState } from 'react';

export default function Edit({ employee }) {
    // Use post() with _method: 'patch' so multipart file uploads work with PATCH routes
    const { data, setData, post, errors, processing } = useForm({
        _method: 'patch',
        first_name: employee.first_name || '',
        last_name: employee.last_name || '',
        email: employee.email || '',
        phone: employee.phone || '',
        position: employee.position || '',
        salary: employee.salary || '',
        hire_date: employee.hire_date || '',
        status: employee.status || 'active',
        profile_photo: null,
        resume: null,
    });

    const [photoPreview, setPhotoPreview] = useState(null);

    const handlePhotoChange = (e) => {
        const file = e.target.files[0];
        setData('profile_photo', file);
        if (file) {
            setPhotoPreview(URL.createObjectURL(file));
        }
    };

    const handleSubmit = (e) => {
        e.preventDefault();
        post(`/employees/${employee.id}`);
    };

    const inputStyle = (error) => ({
        width: '100%',
        padding: '10px',
        borderRadius: '4px',
        border: error ? '2px solid #dc3545' : '1px solid #ddd',
        fontSize: '14px',
        boxSizing: 'border-box'
    });

    const formGroupStyle = { marginBottom: '20px' };
    const labelStyle = { display: 'block', marginBottom: '8px', fontWeight: 'bold', color: '#333' };
    const errorStyle = { color: '#dc3545', fontSize: '12px', marginTop: '5px' };

    const currentPhoto = photoPreview || employee.profile_photo_url;

    return (
        <div style={{ padding: '30px', backgroundColor: '#f5f5f5', minHeight: '100vh' }}>
            <div style={{ maxWidth: '600px', margin: '0 auto', background: 'white', padding: '30px', borderRadius: '4px', boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
                <h1 style={{ marginBottom: '30px', color: '#333' }}>Edit Employee</h1>

                <form onSubmit={handleSubmit}>
                    <div style={formGroupStyle}>
                        <label style={labelStyle}>First Name *</label>
                        <input type="text" value={data.first_name} onChange={(e) => setData('first_name', e.target.value)} style={inputStyle(errors.first_name)} />
                        {errors.first_name && <p style={errorStyle}>{errors.first_name}</p>}
                    </div>

                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Last Name *</label>
                        <input type="text" value={data.last_name} onChange={(e) => setData('last_name', e.target.value)} style={inputStyle(errors.last_name)} />
                        {errors.last_name && <p style={errorStyle}>{errors.last_name}</p>}
                    </div>

                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Email *</label>
                        <input type="email" value={data.email} onChange={(e) => setData('email', e.target.value)} style={inputStyle(errors.email)} />
                        {errors.email && <p style={errorStyle}>{errors.email}</p>}
                    </div>

                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Phone</label>
                        <input type="text" value={data.phone} onChange={(e) => setData('phone', e.target.value)} style={inputStyle(errors.phone)} />
                        {errors.phone && <p style={errorStyle}>{errors.phone}</p>}
                    </div>

                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Position *</label>
                        <input type="text" value={data.position} onChange={(e) => setData('position', e.target.value)} style={inputStyle(errors.position)} />
                        {errors.position && <p style={errorStyle}>{errors.position}</p>}
                    </div>

                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Salary *</label>
                        <input type="number" step="0.01" value={data.salary} onChange={(e) => setData('salary', e.target.value)} style={inputStyle(errors.salary)} />
                        {errors.salary && <p style={errorStyle}>{errors.salary}</p>}
                    </div>

                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Hire Date *</label>
                        <input type="date" value={data.hire_date} onChange={(e) => setData('hire_date', e.target.value)} style={inputStyle(errors.hire_date)} />
                        {errors.hire_date && <p style={errorStyle}>{errors.hire_date}</p>}
                    </div>

                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Status *</label>
                        <select value={data.status} onChange={(e) => setData('status', e.target.value)} style={inputStyle(errors.status)}>
                            <option value="active">Active</option>
                            <option value="inactive">Inactive</option>
                        </select>
                        {errors.status && <p style={errorStyle}>{errors.status}</p>}
                    </div>

                    {/* Profile Photo */}
                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Profile Photo</label>
                        {currentPhoto && (
                            <img
                                src={currentPhoto}
                                alt="Profile"
                                style={{ width: '80px', height: '80px', borderRadius: '50%', objectFit: 'cover', marginBottom: '10px', display: 'block', border: '2px solid #ddd' }}
                            />
                        )}
                        <input
                            type="file"
                            accept="image/jpg,image/jpeg,image/png,image/gif,image/webp"
                            onChange={handlePhotoChange}
                            style={{ ...inputStyle(errors.profile_photo), padding: '6px' }}
                        />
                        <p style={{ fontSize: '12px', color: '#888', marginTop: '4px' }}>
                            {employee.profile_photo_url ? 'Upload a new photo to replace the current one.' : 'JPG, PNG, GIF, WEBP — max 2MB'}
                        </p>
                        {errors.profile_photo && <p style={errorStyle}>{errors.profile_photo}</p>}
                    </div>

                    {/* Resume */}
                    <div style={formGroupStyle}>
                        <label style={labelStyle}>Resume</label>
                        {employee.resume_url && (
                            <a
                                href={employee.resume_url}
                                target="_blank"
                                rel="noreferrer"
                                style={{ display: 'inline-block', marginBottom: '10px', color: '#007bff', fontSize: '13px' }}
                            >
                                View current resume
                            </a>
                        )}
                        <input
                            type="file"
                            accept=".pdf,.doc,.docx"
                            onChange={(e) => setData('resume', e.target.files[0])}
                            style={{ ...inputStyle(errors.resume), padding: '6px' }}
                        />
                        <p style={{ fontSize: '12px', color: '#888', marginTop: '4px' }}>
                            {employee.resume_url ? 'Upload a new file to replace the current resume.' : 'PDF, DOC, DOCX — max 5MB'}
                        </p>
                        {errors.resume && <p style={errorStyle}>{errors.resume}</p>}
                    </div>

                    <div style={{ display: 'flex', gap: '10px', marginTop: '30px' }}>
                        <button
                            type="submit"
                            disabled={processing}
                            style={{ background: '#007bff', color: 'white', padding: '10px 30px', border: 'none', borderRadius: '4px', cursor: processing ? 'not-allowed' : 'pointer', fontSize: '14px', fontWeight: 'bold', opacity: processing ? 0.6 : 1 }}
                        >
                            {processing ? 'Updating...' : 'Update Employee'}
                        </button>
                        <Link
                            href="/employees"
                            style={{ background: '#6c757d', color: 'white', padding: '10px 30px', borderRadius: '4px', cursor: 'pointer', fontSize: '14px', fontWeight: 'bold', textDecoration: 'none', display: 'inline-block', lineHeight: '1.5' }}
                        >
                            Cancel
                        </Link>
                    </div>
                </form>
            </div>
        </div>
    );
}
