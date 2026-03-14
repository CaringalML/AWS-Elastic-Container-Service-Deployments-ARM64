<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class IotEvent extends Model
{
    public $timestamps = false; // table only has created_at, managed by DB default

    protected $fillable = [
        'device_id',
        'event_type',
        'button',
        'message',
        'battery_pct',
        'metadata',
    ];

    protected $casts = [
        'battery_pct' => 'float',
        'metadata'    => 'array',
        'created_at'  => 'datetime',
    ];
}
