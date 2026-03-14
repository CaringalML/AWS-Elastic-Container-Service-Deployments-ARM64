<?php

namespace App\Http\Controllers;

use App\Models\IotEvent;
use Illuminate\Http\Request;
use Inertia\Inertia;

class IotEventController extends Controller
{
    // Renders the IoT Live Data page (full Inertia page load)
    public function index()
    {
        return Inertia::render('IoT/Index');
    }

    // JSON endpoint polled by the React page every 3 seconds
    public function events(Request $request)
    {
        $events = IotEvent::orderByDesc('created_at')
            ->limit(50)
            ->get();

        return response()->json($events);
    }
}
