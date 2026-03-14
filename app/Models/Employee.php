<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Storage;

class Employee extends Model
{
    protected $fillable = [
        'first_name',
        'last_name',
        'email',
        'phone',
        'position',
        'salary',
        'hire_date',
        'status',
        'profile_photo',
        'resume',
    ];

    protected $appends = [
        'profile_photo_url',
        'resume_url',
    ];

    protected $casts = [
        'hire_date' => 'date',
        'salary'    => 'decimal:2',
    ];

    public function getFullNameAttribute(): string
    {
        return $this->first_name . ' ' . $this->last_name;
    }

    // Returns the public URL for the profile photo (local /storage/... or S3 CDN URL)
    public function getProfilePhotoUrlAttribute(): ?string
    {
        return $this->profile_photo ? Storage::url($this->profile_photo) : null;
    }

    // Returns the public URL for the resume file
    public function getResumeUrlAttribute(): ?string
    {
        return $this->resume ? Storage::url($this->resume) : null;
    }
}
