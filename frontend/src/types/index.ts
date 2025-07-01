export interface Message {
  id: string;
  content: string;
  timestamp: string;
}

export interface ApiResponse {
  message: string;
  data: any[];
}
