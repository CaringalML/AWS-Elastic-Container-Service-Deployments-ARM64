<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('iot_events', function (Blueprint $table) {
            $table->id();
            $table->string('device_id', 64)->index();
            $table->string('event_type', 64)->index();
            $table->string('button', 32)->nullable();
            $table->text('message')->nullable();
            $table->decimal('battery_pct', 5, 2)->nullable();
            $table->jsonb('metadata')->nullable();
            $table->timestamp('created_at')->useCurrent()->index();
            // No updated_at — IoT events are append-only
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('iot_events');
    }
};
