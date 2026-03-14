<?php

namespace App\Http\Controllers;

use App\Models\Employee;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Inertia\Inertia;

class EmployeeController extends Controller
{
    public function index()
    {
        $employees = Employee::all();
        return Inertia::render('Employees/Index', [
            'employees' => $employees,
        ]);
    }

    public function create()
    {
        return Inertia::render('Employees/Create');
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'first_name'    => 'required|string|max:255',
            'last_name'     => 'required|string|max:255',
            'email'         => 'required|email|unique:employees',
            'phone'         => 'nullable|string|max:20',
            'position'      => 'required|string|max:255',
            'salary'        => 'required|numeric|min:0',
            'hire_date'     => 'required|date',
            'status'        => 'required|in:active,inactive',
            'profile_photo' => 'nullable|image|mimes:jpg,jpeg,png,gif,webp|max:2048',
            'resume'        => 'nullable|file|mimes:pdf,doc,docx|max:5120',
        ]);

        if ($request->hasFile('profile_photo')) {
            $validated['profile_photo'] = $request->file('profile_photo')
                ->store('employees/photos');
        }

        if ($request->hasFile('resume')) {
            $validated['resume'] = $request->file('resume')
                ->store('employees/resumes');
        }

        Employee::create($validated);
        return redirect()->route('employees.index')->with('success', 'Employee created successfully');
    }

    public function edit(Employee $employee)
    {
        return Inertia::render('Employees/Edit', [
            'employee' => $employee,
        ]);
    }

    public function update(Request $request, Employee $employee)
    {
        $validated = $request->validate([
            'first_name'    => 'required|string|max:255',
            'last_name'     => 'required|string|max:255',
            'email'         => 'required|email|unique:employees,email,' . $employee->id,
            'phone'         => 'nullable|string|max:20',
            'position'      => 'required|string|max:255',
            'salary'        => 'required|numeric|min:0',
            'hire_date'     => 'required|date',
            'status'        => 'required|in:active,inactive',
            'profile_photo' => 'nullable|image|mimes:jpg,jpeg,png,gif,webp|max:2048',
            'resume'        => 'nullable|file|mimes:pdf,doc,docx|max:5120',
        ]);

        if ($request->hasFile('profile_photo')) {
            if ($employee->profile_photo) {
                Storage::delete($employee->profile_photo);
            }
            $validated['profile_photo'] = $request->file('profile_photo')
                ->store('employees/photos');
        }

        if ($request->hasFile('resume')) {
            if ($employee->resume) {
                Storage::delete($employee->resume);
            }
            $validated['resume'] = $request->file('resume')
                ->store('employees/resumes');
        }

        $employee->update($validated);
        return redirect()->route('employees.index')->with('success', 'Employee updated successfully');
    }

    public function destroy(Employee $employee)
    {
        if ($employee->profile_photo) {
            Storage::delete($employee->profile_photo);
        }
        if ($employee->resume) {
            Storage::delete($employee->resume);
        }

        $name = $employee->full_name;
        $employee->delete();
        return to_route('employees.index')->with('success', "Employee '$name' deleted successfully");
    }
}
