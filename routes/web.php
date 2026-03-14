<?php

use App\Http\Controllers\EmployeeController;
use App\Http\Controllers\IotEventController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return redirect('/employees');
});

// ALB health check endpoint — must return 200 (ALB does not follow redirects)
Route::get('/health', function () {
    return response('OK', 200);
});

Route::resource('employees', EmployeeController::class);

// IoT Live Data
Route::get('/iot', [IotEventController::class, 'index'])->name('iot.index');
Route::get('/iot-events', [IotEventController::class, 'events'])->name('iot.events');