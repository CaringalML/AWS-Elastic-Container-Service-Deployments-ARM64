<?php

use App\Http\Controllers\EmployeeController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return redirect('/employees');
});

// ALB health check endpoint — must return 200 (ALB does not follow redirects)
Route::get('/health', function () {
    return response('OK', 200);
});

Route::resource('employees', EmployeeController::class);