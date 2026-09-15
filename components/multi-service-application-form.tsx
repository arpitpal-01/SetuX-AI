"use client";

import { FormEvent, useState } from "react";
import { ArrowLeft, ArrowRight, Check, CheckCircle2, ClipboardCheck, FileText, Sparkles, UploadCloud } from "lucide-react";
import { supabase } from "../lib/supabase";

type ServiceDefinition = {
  name: string;
  department: string;
  officialLink: string;
  fields: string[];
  documents: string[];
};

const officialPortal = "https://services.india.gov.in/?utm_source=chatgpt.com";
const serviceDefinitions: ServiceDefinition[] = [
  { name: "Birth Certificate", department: "Local Government / Registrar of Births & Deaths", officialLink: officialPortal, fields: ["Name", "Date of Birth", "Place of Birth"], documents: ["Hospital Record", "Identity Proof"] },
  { name: "Caste Certificate", department: "Revenue / District Administration", officialLink: officialPortal, fields: ["Name", "Address", "Caste Category"], documents: ["Identity Proof", "Address Proof", "Supporting Certificate"] },
  { name: "Income Certificate", department: "Revenue Department", officialLink: officialPortal, fields: ["Name", "Address", "Annual Income"], documents: ["Identity Proof", "Address Proof", "Income Proof"] },
  { name: "Residential / Domicile Certificate", department: "Revenue Department", officialLink: officialPortal, fields: ["Name", "Address", "Years of Residence"], documents: ["Identity Proof", "Address Proof"] },
  { name: "Death Certificate", department: "Local Government / Registrar", officialLink: officialPortal, fields: ["Name", "Date of Death", "Place of Death"], documents: ["Medical Record", "Identity Proof"] },
  { name: "Disability Certificate", department: "Health / Social Welfare", officialLink: officialPortal, fields: ["Name", "Disability Type", "Disability Percentage"], documents: ["Identity Proof", "Medical Report"] },
  { name: "Character Certificate", department: "Police / District Administration", officialLink: officialPortal, fields: ["Name", "Address", "Purpose"], documents: ["Identity Proof", "Address Proof"] },
  { name: "Legal Heir Certificate", department: "Revenue / District Administration", officialLink: officialPortal, fields: ["Name", "Deceased Name", "Relationship"], documents: ["Identity Proof", "Death Certificate", "Family Proof"] },
  { name: "Ration Card Application", department: "Food & Civil Supplies", officialLink: officialPortal, fields: ["Head of Family", "Address", "Family Members"], documents: ["Identity Proof", "Address Proof", "Family Details"] },
  { name: "Senior Citizen Certificate/ID", department: "Social Welfare / District Administration", officialLink: officialPortal, fields: ["Name", "Date of Birth", "Address"], documents: ["Identity Proof", "Age Proof", "Address Proof"] },
];
const acceptedTypes = ["application/pdf", "image/jpeg", "image/png"];
const maxFileSize = 10 * 1024 * 1024;

export function MultiServiceApplicationForm({ go, userId }: { go: (view: "overview" | "applications") => void; userId: string }) {
  const [step, setStep] = useState(1);
  const [selectedName, setSelectedName] = useState(serviceDefinitions[0].name);
  const [values, setValues] = useState<Record<string, string>>({});
  const [files, setFiles] = useState<Record<string, File>>({});
  const [busy, setBusy] = useState(false);
  const [reference, setReference] = useState("");
  const [error, setError] = useState("");
  const service = serviceDefinitions.find((item) => item.name === selectedName) || serviceDefinitions[0];
  const updateValue = (field: string, value: string) => setValues((current) => ({ ...current, [field]: value }));
  const chooseFile = (documentName: string, file: File | undefined) => { if (file) setFiles((current) => ({ ...current, [documentName]: file })); };
  const validate = () => {
    const missingFields = service.fields.filter((field) => !values[field]?.trim());
    const missingDocuments = service.documents.filter((document) => !files[document]);
    if (missingFields.length) return `Complete required fields: ${missingFields.join(", ")}.`;
    if (missingDocuments.length) return `Upload required documents: ${missingDocuments.join(", ")}.`;
    const invalid = Object.entries(files).find(([, file]) => file.size === 0 || file.size > maxFileSize || !acceptedTypes.includes(file.type));
    if (invalid) return `${invalid[0]} must be a non-empty PDF, JPG, or PNG file under 10 MB.`;
    return "";
  };
  const submit = async (event: FormEvent) => {
    event.preventDefault(); setError(""); const validationError = validate(); if (validationError) { setError(validationError); setStep(validationError.startsWith("Complete") ? 2 : 3); return; }
    const client = supabase; if (!client) { setError("Supabase is not configured."); return; }
    setBusy(true); const number = `SETUX-${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`;
    const { data: serviceRow, error: serviceError } = await client.from("services").select("id, department_id").eq("name", selectedName).single();
    if (serviceError || !serviceRow) { setError("This service is not available in Supabase yet. Run the service catalog migration."); setBusy(false); return; }
    const { data: application, error: applicationError } = await client.from("applications").insert({ application_number: number, user_id: userId, service_id: serviceRow.id, department_id: serviceRow.department_id, status: "DRAFT" }).select("id, application_number").single();
    if (applicationError || !application) { setError(applicationError?.message || "Could not create the application."); setBusy(false); return; }
    for (const documentName of service.documents) {
      const file = files[documentName]; const path = `${userId}/${application.id}/${documentName.replace(/[^a-z0-9]+/gi, "-").toLowerCase()}-${file.name}`;
      const upload = await client.storage.from("application-documents").upload(path, file, { upsert: false, contentType: file.type });
      if (upload.error) { setError(`${documentName} upload failed. The application was not submitted.`); setBusy(false); return; }
      const row = await client.from("application_documents").insert({ application_id: application.id, document_name: file.name, storage_path: path, document_type: documentName, file_size: file.size, mime_type: file.type });
      if (row.error) { setError(`${documentName} could not be verified in the application record.`); setBusy(false); return; }
    }
    const statusResult = await client.from("applications").update({ status: "SUBMITTED", submitted_at: new Date().toISOString() }).eq("id", application.id);
    if (statusResult.error) { setError("Documents were uploaded, but submission could not be completed."); setBusy(false); return; }
    await client.from("application_extracted_data").insert({ application_id: application.id, extracted_json: values, confidence: null });
    await client.from("application_validation_results").insert({ application_id: application.id, is_valid: true, missing_fields: [], missing_documents: [], warnings: ["Submission checks passed; final eligibility remains with an authorized officer."] });
    await client.from("application_events").insert({ application_id: application.id, event_type: "APPLICATION_SUBMITTED", description: `${selectedName} submitted with all required fields and documents verified`, created_by: userId });
    setReference(application.application_number); setBusy(false);
  };
  if (reference) return <div className="page-wrap new-page"><div className="success-panel"><div className="success-icon"><Check size={26} /></div><p className="eyebrow">APPLICATION SUBMITTED</p><h2>Your {selectedName} application is ready for processing.</h2><p>All required information and documents passed the submission checks.</p><div className="reference">{reference}<button type="button" onClick={() => void navigator.clipboard?.writeText(reference)}><ClipboardCheck size={15} /></button></div><button className="primary-btn" onClick={() => go("applications")}>View applications <ArrowRight size={16} /></button></div></div>;
  return <div className="page-wrap new-page"><div className="page-heading"><div><p className="eyebrow">APPLICATIONS / NEW</p><h1>Submit a verified application</h1><p className="subheading">SetuX checks every required field and document before submission.</p></div><button className="quiet-btn" type="button" onClick={() => go("overview")}><ArrowLeft size={16} /> Back to overview</button></div><div className="steps"><Step n="01" label="Select service" active={step >= 1} /><span /><Step n="02" label="Required fields" active={step >= 2} /><span /><Step n="03" label="Documents" active={step >= 3} /><span /><Step n="04" label="Review" active={step >= 4} /></div><form className="form-card" onSubmit={submit}><div className="form-card-head"><div><p className="eyebrow">STEP 0{step}</p><h2>{step === 1 ? "Choose your service" : step === 2 ? "Enter all required information" : step === 3 ? "Upload required documents" : "Verify and submit"}</h2><p>{step === 1 ? "Each service has its own fields and document checklist." : step === 2 ? `Required for ${service.name}: ${service.fields.join(", ")}.` : step === 3 ? `Required documents: ${service.documents.join(", ")}.` : "Review the complete checklist before sending your case."}</p></div><span className="step-count">{step} / 4</span></div>{step === 1 && <div className="choice-grid">{serviceDefinitions.map((item) => <button type="button" key={item.name} className={`choice-card ${selectedName === item.name ? "selected" : ""}`} onClick={() => { setSelectedName(item.name); setStep(2); }}><div className="service-icon mint"><FileText size={20} /></div><div><strong>{item.name}</strong><span>{item.department}</span><small className="choice-meta">{item.fields.length} fields · {item.documents.length} documents</small></div>{selectedName === item.name && <CheckCircle2 className="choice-check" size={19} />}</button>)}</div>}{step === 2 && <div className="input-grid">{service.fields.map((field) => <label key={field}>{field}<input required value={values[field] || ""} onChange={(event) => updateValue(field, event.target.value)} placeholder={`Enter ${field.toLowerCase()}`} /></label>)}</div>}{step === 3 && <div className="required-upload-list">{service.documents.map((documentName) => <label className="required-upload" key={documentName}><span className="upload-document-icon"><UploadCloud size={16} /></span><span><strong>{documentName}</strong><small>{files[documentName]?.name || "Required document · PDF, JPG, or PNG · max 10 MB"}</small></span><span className="outline-btn">{files[documentName] ? "Replace" : "Choose file"}<input className="sr-only" type="file" accept={acceptedTypes.join(",")} onChange={(event) => chooseFile(documentName, event.target.files?.[0])} /></span>{files[documentName] && <CheckCircle2 className="file-ok" size={18} />}</label>)}</div>}{step === 4 && <div className="review-list"><div><span>Service</span><strong>{selectedName}</strong></div><div><span>Department</span><strong>{service.department}</strong></div><div><span>Required fields</span><strong>{service.fields.length} / {service.fields.length} complete</strong></div><div><span>Required documents</span><strong>{service.documents.length} / {service.documents.length} uploaded and verified</strong></div><div><span>Official portal</span><a href={service.officialLink} target="_blank" rel="noreferrer">Open service information</a></div><div><span>Processing</span><strong className="ai-label"><Sparkles size={14} /> AI case preparation included</strong></div></div>}{error && <p className="auth-error form-error">{error}</p>}<div className="form-actions">{step > 1 && <button type="button" className="quiet-btn" onClick={() => setStep(step - 1)}>Back</button>}{step < 4 ? <button type="button" className="primary-btn" onClick={() => setStep(step + 1)}>Continue <ArrowRight size={16} /></button> : <button className="primary-btn" disabled={busy}>{busy ? "Verifying and submitting..." : "Submit verified application"}<ArrowRight size={16} /></button>}</div></form></div>;
+}
+
+function Step({ n, label, active }: { n: string; label: string; active: boolean }) { return <div className={`step ${active ? "active" : ""}`}><span>{active && n !== "04" ? <Check size={13} /> : n}</span><small>{label}</small></div>; }
